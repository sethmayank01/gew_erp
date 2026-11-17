# Release 1.2.10+10

Date: 24 October 2026.

## Changes

- Transactional stock/indent writes, safe retries, collision protection, and stale
  edit checks from the write-safety audit.
- Signed login tokens and server-enforced administrator permissions. Tokens expire
  after one hour; users must log in again. Existing tokens are not immediately
  revoked by a password reset or account deletion. Use HTTPS/network restrictions
  for credential protection; the existing LAN HTTP setup is unchanged.
- Outgoing selection/search responses cannot overwrite newer choices. Issuing is
  blocked while quantities load or a load has failed; explicit retries are offered.
- Includes the existing generic vector-group, corrected load-loss, individual
  winding report, transparent watermark, and update-gating changes.

## Verification

- Python: 33 passing tests, temporary database tables only.
- Flutter: 92 passing application tests, including six outgoing loading regressions.
- Windows release executable metadata: 1.2.10+10; Windows installer compiled.
- Android APK: versionName 1.2.10, versionCode 10; signature verified and signing
  certificate matches the existing APK for in-place upgrades. This preserves the
  existing Android debug signing configuration; changing release keys requires a
  separate migration plan.
- Live deployment completed at 12:30 IST. `FlaskAppService` is Running and the LAN
  `/health` endpoint reports `status: OK`, `version: 1.2.10`.
- All five deployed runtime files match the verified workspace hashes. Live checks
  passed for authenticated reads, unauthenticated/invalid-token rejection, and
  administrator access restrictions. The update manifest advertises both 1.2.10
  downloads, whose sizes and copied-file SHA-256 checks were verified.
- The first rollout attempt rolled back after PowerShell converted the null
  `File.Replace` backup argument to an empty path. The explicit backup-path fix was
  reproduced locally and the retry succeeded. No production rows were changed.

Artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| Android APK | `7D1EFD6F5970DF822A8122DD1BE29776E2574AEEAD77849E7C12AE232439CE2F` |
| Windows installer | `BE4CC295127538A0BE2F94DF29A27C861F8D892BD16251A0BD5096F5989B31D0` |

## Deployment

The approved rollout targets `FlaskAppService`, whose application directory is
`C:\Users\Admin\flask_backend`, and the update host
`C:\Users\Public\gew_erp` on port 8000. The workspace is not the running backend.

`scripts/deploy_release.ps1` copies five runtime modules, configures a persistent
service-specific signing key, restarts the service without Flask debug mode,
performs read-only authentication/health checks, and publishes the new manifest
last. Existing APK/installer URLs and files remain untouched; new packages use
`/releases/1.2.10/` URLs. No database schema migration is required.

Clients must install the update and log in again. Old clients do not send tokens
and cannot access the new authenticated API. Publishing downloads does not install
them automatically on users' computers or phones.

## Rollback

The deployment script prints its timestamped workspace backup directory. Before
rollback, stop `FlaskAppService`. Copy the saved `app.py` and `stock_issue.py` (and
any other backed-up runtime modules) to the backend directory, restore the saved
`Version.json` to the public update directory, then start the service and verify
`/health`. Newly added unused helper modules and the signing key can remain: the
previous backend does not use them. No production data was rewritten by deployment,
so there is no database migration to reverse.

Successful rollout backup:
`C:\Users\Admin\gew_erp\tmp\deployment-backup-1.2.10-20261024T123005`.
Deployment transcript: `tmp/deployment_1.2.10.log`.

Already updated clients cannot safely use all new write contracts against the old
backend. Restore service promptly or keep clients out of write workflows during a
rollback; do not assume a server rollback also rolls back installed clients.

## Separate Data Reconciliation

Seven suspected duplicate indent pairs remain untouched. Their identifiers and
issuance observations are recorded in `docs/write_safety_audit_2026-10-23.md`.
The previously authorized TRFD0721 repair is unchanged.
