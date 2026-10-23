# GEW ERP Write-Safety Audit

Date: 23 October 2026. Scope: duplicate submissions, retries, concurrency,
transaction boundaries, and error handling across the Flask backend and Flutter
write workflows. Calculations, report persistence, and update gating were also
checked. This is a source review and targeted reproduction exercise, not a
certification that every execution path is defect-free.

No production records were changed during this audit. Database inspection was
read-only; write reproductions used connection-local temporary tables through
Flask's local test client. None of the findings below has been fixed in production
as part of this audit.

## Highest-Priority Findings

### 1. P1: Incoming submissions can create duplicate stock on retry

Sources: `lib/screens/material_incoming_screen.dart:159`,
`lib/services/api_service.dart:173`, `flaskcode/app.py:722`.

The submit button has no in-flight guard. The API client adds a UUID, but the
backend ignores it as the receipt identity and generates another UUID for every
POST. Repeating exactly the same payload creates two receipts. Approving each
receipt then creates two stock lots. The existing approval lock prevents repeated
approval of ONE receipt, not duplicate receipts from repeated submissions.

Reproduced: two identical submissions of five units, followed by approval, create
ten units of stock instead of five.

Fix direction: one retained client operation ID per submission/retry, backend
idempotency on that ID, and a UI single-flight guard. Do not deduplicate by invoice:
separate legitimate lots can share an invoice number.

### 2. P1: Concurrent new-job entry can silently overwrite a different job

Sources: `lib/screens/job_details_screen.dart:100`, `flaskcode/app.py:488`.

Job numbers are calculated from a client-side read of the current maximum. Two
users can choose the same next number before either saves. The shared create/update
endpoint uses `ON CONFLICT (serial_no) DO UPDATE SET data = EXCLUDED.data`, so the
second save replaces the first job rather than reporting a collision. Existing
indents and reports can then refer to a job whose customer/specification changed.

Reproduced: creating two different customers under one job number returns success
twice and retains only the second customer's data.

Fix direction: allocate numbers in the backend and distinguish create from update.
Reject duplicate creation; use revision checking or field-level updates for edits.

### 3. P1: Editing indent quantity leaves outstanding demand incorrect

Sources: `flaskcode/app.py:2035`,
`lib/screens/job_indent_consumption.dart` admin update path.

`/job_indents/update_existing` changes only the job-indent JSON quantity. It does
not update the corresponding `indent_stock.indentQuantity`, even though new indent
creation and stock issuance both maintain that aggregate. It also does not validate
finite positive quantities or guard reductions against already-issued quantities.

Reproduced: an indent changes from 10 to 20, but outstanding demand remains 10.

Fix direction: lock the indent and aggregate and apply the change in outstanding
demand in the same transaction. Explicitly account for prior issuance and the
existing tolerance policy.

### 4. P1: Incoming/stock deletion is not an atomic, issuance-aware operation

Sources: `lib/screens/material_incoming_screen.dart:191`,
`flaskcode/app.py:949`, `flaskcode/app.py:1375`.

The UI deletes stock and the incoming receipt in two independent requests. The
stock-delete boolean is ignored, and the receipt-delete wrapper ignores HTTP
failure status. A partial failure can leave approved stock without its receipt,
or an approved receipt without stock. The backend receipt-delete endpoint itself
does not reconcile stock. Stock deletion does not check outgoing allocations before
deleting a lot, including a partly consumed lot.

Reproduced: deleting an approved receipt leaves its stock lot behind.

Fix direction: one server-side transaction that locks the receipt and stock lot,
checks issuance history, and either rejects deletion or performs an explicit,
auditable reversal. Do not silently remove consumed inventory history.

### 5. P1: Server-side authorization is absent from sensitive writes

Sources: `flaskcode/app.py:96`, `flaskcode/app.py:767`,
`lib/services/api_service.dart` request headers.

Login returns user details but establishes no authenticated server session/token.
Sensitive endpoints have no authentication/role middleware. For example, approval
accepts an arbitrary nonempty `approver` string supplied by the caller; it does not
verify that the caller is a logged-in administrator. UI role restrictions do not
protect direct API calls, modified clients, or older builds.

Reproduced: a local test-client request approves stock without logging in, using a
caller-supplied approver name.

Fix direction: authenticated requests, server-enforced permissions, and audit
identity derived from authentication, not request-body usernames. Plan client/server
compatibility before rollout.

## Additional Confirmed Findings

### 6. P2: Legacy issuance endpoints still accept repeat mutations

Sources: `flaskcode/app.py:1651`, `flaskcode/app.py:1749`,
`lib/services/api_service.dart:413`.

`PUT /job_indents` adds `issuedQty`/`issuedValue` to the stored totals without an
operation ID or row lock. Replaying a request increments totals twice. It is also
separate from stock deduction and the outgoing ledger. The legacy `issueMaterial`
helper still performs split writes, including a POST to `/stock`, for which the
current backend has no POST route. The current outgoing screen uses the newer
atomic endpoint, but old clients can still reach the legacy routes.

Reproduced: sending the same two-unit legacy update twice records four issued units.

Fix direction: retire legacy mutations safely or route supported requests through
one atomic, idempotent issuance operation. Reject unsupported old workflows instead
of partially applying them.

### 7. P2: Several API writes report success despite HTTP errors

Sources: `lib/services/api_service.dart:119`, `:137`, `:173`, `:222`;
`lib/screens/stock_view_screen.dart:223`.

Report saves, job saves, incoming submissions, and receipt deletion await HTTP but
do not validate response status. A 400/409/500 response therefore completes normally;
screens can display success, clear inputs, or navigate away even though nothing was
saved. Stock deletion similarly removes the row from the local UI without checking
the returned success flag. Some newer methods do check status, so behavior differs
between screens.

Fix direction: a shared response-validation contract, explicit handling of conflicts
and unknown network outcomes, and clearing inputs only after confirmed success.

### 8. P2: Material creation permits duplicate catalog definitions

Sources: `lib/screens/material_list_screen.dart:94`, `flaskcode/app.py:580`.

Each material POST gets a new server UUID. Conflict handling is on that fresh UUID,
not on the type/subtype business identity. The live schema has no type/subtype unique
constraint. Repeat submission creates identical material definitions. Screens key
quantity controllers by type/subtype, so duplicate catalog entries can also cause
duplicate line generation or conflicting UI controls.

Reproduced: two identical material requests create two catalog rows.

Read-only live inspection found no duplicate catalog definitions at audit time.

Fix direction: agreed normalization and a business-key unique constraint, with
create/update separation and a UI single-flight guard.

### 9. P2: Report deletion uses the wrong URL and HTTP method

Sources: `lib/services/api_service.dart:123`, `flaskcode/app.py:395`.

Flutter calls `POST /reports/delete`; the backend implements `DELETE /reports`.
The app's request receives 404 rather than deleting a report.

Reproduced using the app's exact route/method against the local Flask router.

Fix direction: align the client/server contract and use stable report IDs rather
than only author/timestamp identity where practical.

## Additional Concurrency Risks Found by Source Inspection

These are supported by the code paths but were not reproduced with two simultaneous
database sessions in this audit.

- Incoming edit versus approval: `flaskcode/app.py:1033` reads without `FOR UPDATE`,
  checks `approved`, then writes the old JSON snapshot back. Approval can commit in
  between. The edit can restore `approved: false` and stale receipt fields after
  stock has already been created. Approval's row lock does not protect an earlier,
  unlocked reader. Lock the receipt before checking/editing approval state.
- Stale stock edit versus issuance: `flaskcode/stock_issue.py:25` sets an absolute
  balance supplied from an earlier UI snapshot. Locking the write does not detect
  that stock was issued while an administrator had the edit dialog open. Add a
  revision/expected-balance check and record adjustments explicitly.
- Changing job/material while outgoing data loads can attach an older async response
  to the current selection (`lib/screens/material_outgoing_screen.dart:123`). The
  atomic backend validates allocations and blocks wrong stock deductions, but the
  screen can show incorrect availability and reject otherwise valid requests.

## Read-Only Live Data Findings

The previously authorized TRFD0721 repair remains applied. Seven OTHER repeated
job/material pairs remain. These match in quantity and user and have closely spaced
creation timestamps. They need individual reconciliation, not a bulk delete.

| Job | Material subtype | Quantity per row | Row IDs |
| --- | --- | ---: | --- |
| TRFD0654 | AT_HT_Arching_Horn | 3 | 440, 441 |
| TRFD0674 | Tank_Blasting_Charges | 1400 | 3137, 3138 |
| TRFD0693 | Bolt_1/2x40 | 10 | 2096, 2100 |
| TRFD0693 | Bolt_M10x30 | 1.5 | 2097, 2101 |
| TRFD0693 | Bolt_M10x40 | 3 | 2098, 2102 |
| TRFD0693 | Bolt_M8x30_GR4.6 | 1.5 | 2099, 2103 |
| TRFD0712 | SpringWasher_M10 | 0.2 | 6243, 6244 |

For the first six pairs, one row has issuance history and the other does not. Neither
TRFD0712 row has issuance history. No repair of these rows was attempted.

## Verification and Deployment

- Eight executable safety reproductions were added in
  `flaskcode/test_write_audit.py`. They are marked `expectedFailure` because the
  existing implementation violates those safety assertions. An expected failure is
  evidence of an unresolved defect, not a production fix.
- The complete Python suite has 12 passing stock/indent regression tests and eight
  expected failures for the confirmed audit defects. It uses temporary tables only.
- Full Flutter tests were run. The first run exposed fixture type errors in the
  previously added below/above-rated-current tests. Those fixtures were corrected
  without changing calculation implementation. The repeat run finished with 75
  passing application tests and three failing older smoke tests. The machine log
  additionally reports 13 successful hidden suite-loading steps; those are not
  counted as application tests.
- Three older smoke tests have independent problems: the outgoing screen test lacks
  HTTP mocks and looks for the wrong submit text; the report-input test lacks HTTP
  mocks; and `test/widget_test.dart` still expects Flutter's sample counter app.
  They should be replaced with realistic application tests, not silently skipped.
- The new atomic outgoing path and one-receipt approval retry handling already have
  safeguards. The indent single-flight/backend duplicate guard added earlier also
  passed its focused tests.
- Read-only inspection of `C:\Users\Admin\flask_backend\app.py` shows the running
  service file still contains the old unconditional indent insertion route. The new
  `indent_submission.py` guard is present only in the workspace until deployed.
  Updating Flutter source alone does not update the Windows service or existing
  installed clients.

## Recommended Order

1. Deploy the already-tested indent creation guard and rebuild the client UI guard.
2. Make incoming submission idempotent and receipt/stock deletion transactional.
3. Protect job-number allocation and indent quantity edits.
4. Add server-side authorization with a compatible client rollout.
5. Retire unsafe legacy writes, standardize response handling, and fix catalog/report
   contracts.
6. Review the seven historical repeated indent pairs, taking backups and reconciling
   outstanding demand before any authorized cleanup.
