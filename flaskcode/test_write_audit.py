"""Safety regressions for the audit findings; only temporary tables are used."""
import os
import unittest
from unittest.mock import patch

import psycopg2
from psycopg2.extras import Json

import app
import bcrypt
from authentication import verify_token
from test_support import authenticated_client


class WriteAuditTests(unittest.TestCase):
    def setUp(self):
        self.conn = psycopg2.connect(
            host=os.environ['ERP_TEST_DB_HOST'], database=app.DB_NAME,
            user=app.DB_USER, password=app.DB_PASS, connect_timeout=5,
        )
        self.addCleanup(self.conn.close)
        with self.conn.cursor() as cur:
            for statement in (
                'CREATE TEMP TABLE incoming_materials (id text PRIMARY KEY, data jsonb)',
                'CREATE TEMP TABLE stock (id text PRIMARY KEY, key text, data jsonb)',
                'CREATE TEMP TABLE jobs (serial_no text PRIMARY KEY, data jsonb)',
                'CREATE TEMP TABLE materials (id text PRIMARY KEY, type text, subtype text, data jsonb)',
                'CREATE TEMP TABLE job_indents (id serial PRIMARY KEY, jobid text, data jsonb)',
                'CREATE TEMP TABLE indent_stock (key text PRIMARY KEY, data jsonb)',
                'CREATE TEMP TABLE outgoing_materials (id text PRIMARY KEY, data jsonb)',
                'CREATE TEMP TABLE reports (id serial PRIMARY KEY, data jsonb)',
                'CREATE TEMP TABLE users (username text PRIMARY KEY, password text, role text)',
            ):
                cur.execute(statement)
        self.conn.commit()

        connection = self.conn

        class ConnectionProxy:
            def __getattr__(self, name):
                return getattr(connection, name)

            def __enter__(self):
                return connection.__enter__()

            def __exit__(self, *args):
                return connection.__exit__(*args)

            def close(self):
                pass

        override = patch.object(app, 'get_db_connection', return_value=ConnectionProxy())
        override.start()
        self.addCleanup(override.stop)
        self.client = authenticated_client(app.app)
        self.incoming = {
            'id': 'client-request-id', 'type': 'Audit', 'subtype': 'Material',
            'quantity': 5, 'price': 10, 'jobSpecific': False,
            'entryDate': '2026-10-23T12:00:00', 'user': 'audit-test',
        }

    def seed_indent(self):
        with self.conn.cursor() as cur:
            cur.execute('INSERT INTO job_indents (jobid, data) VALUES (%s, %s)', (
                'AUDIT-JOB', Json({'serialNo': 'AUDIT-JOB', 'type': 'Audit',
                    'subtype': 'Material', 'quantity': 10, 'issuedQty': 0, 'issuedValue': 0}),
            ))
            cur.execute('INSERT INTO indent_stock VALUES (%s, %s)', (
                'Audit - Material', Json({'indentQuantity': 10}),
            ))
        self.conn.commit()

    def test_incoming_retry_must_not_create_two_receipts_and_double_stock(self):
        ids = []
        for _ in range(2):
            response = self.client.post('/incoming_materials', json=self.incoming)
            self.assertEqual(response.status_code, 201)
            ids.append(response.get_json()['id'])
        for entry_id in ids:
            self.assertEqual(self.client.post(
                f'/incoming_materials/{entry_id}/approve', json={'approver': 'audit-test'},
            ).status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute("SELECT sum((data->>'quantity')::numeric) FROM stock")
            self.assertEqual(float(cur.fetchone()[0]), 5, 'Retry doubled stock to 10')

    def test_new_job_creation_must_not_silently_overwrite_an_existing_job(self):
        for customer in ('First customer', 'Second customer'):
            response = self.client.post('/jobs', json={
                'serialNo': 'AUDIT-JOB', 'jobType': 'New', 'purchaserName': customer,
            })
            self.assertEqual(response.status_code, 201 if customer == 'First customer' else 409)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'purchaserName' FROM jobs WHERE serial_no = 'AUDIT-JOB'")
            self.assertEqual(cur.fetchone()[0], 'First customer', 'Original job was overwritten')

    def test_indent_edit_must_update_outstanding_aggregate(self):
        self.seed_indent()
        response = self.client.post('/job_indents/update_existing', json={
            'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material', 'quantity': 20,
        })
        self.assertEqual(response.status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'indentQuantity' FROM indent_stock")
            self.assertEqual(float(cur.fetchone()[0]), 20, 'Aggregate stayed at 10')

    def test_legacy_issue_update_retry_must_not_double_issued_quantity(self):
        self.seed_indent()
        payload = {'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material',
                   'issuedQty': 2, 'issuedValue': 20, 'out_time': 'same-operation'}
        for _ in range(2):
            self.assertEqual(self.client.put('/job_indents', json=payload).status_code, 410)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'issuedQty' FROM job_indents")
            self.assertEqual(float(cur.fetchone()[0]), 0, 'Legacy issuance must not mutate the indent')

    def test_material_retry_must_not_create_duplicate_catalog_entries(self):
        for _ in range(2):
            response = self.client.post('/materials', json={'type': 'Audit', 'subtype': 'Material'})
            self.assertEqual(response.status_code, 201)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM materials')
            self.assertEqual(cur.fetchone()[0], 1, 'Created two identical material definitions')

    def test_deleting_receipt_must_not_leave_its_approved_stock_orphaned(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        self.assertEqual(self.client.post(
            f'/incoming_materials/{receipt}/approve', json={'approver': 'audit-test'},
        ).status_code, 200)
        self.assertEqual(self.client.delete(f'/incoming_materials/{receipt}').status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM stock')
            self.assertEqual(cur.fetchone()[0], 0, 'Receipt deleted but its approved stock remains')

    def test_approval_must_require_authenticated_approver(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        response = self.client.post(
            f'/incoming_materials/{receipt}/approve', json={'approver': 'someone-else'},
            headers={'Authorization': ''},
        )
        self.assertIn(response.status_code, (401, 403), 'Approval succeeded without login')

    def test_report_delete_url_used_by_app_must_exist(self):
        with self.conn:
            with self.conn.cursor() as cur:
                cur.execute('INSERT INTO reports (data) VALUES (%s)', (Json({
                    'savedBy': 'audit-test', 'timestamp': '2026-10-23T12:00:00',
                }),))
        response = self.client.post('/reports/delete', json={
            'savedBy': 'audit-test', 'timestamp': '2026-10-23T12:00:00',
        })
        self.assertEqual(response.status_code, 200, response.get_json())

    def test_receipt_id_conflict_rejects_changed_payload(self):
        self.assertEqual(self.client.post('/incoming_materials', json=self.incoming).status_code, 201)
        response = self.client.post('/incoming_materials', json={**self.incoming, 'quantity': 99})
        self.assertEqual(response.status_code, 409)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'quantity' FROM incoming_materials")
            self.assertEqual(float(cur.fetchone()[0]), 5)

    def test_same_invoice_can_have_two_legitimate_receipts(self):
        for request_id in ('lot-one', 'lot-two'):
            response = self.client.post('/incoming_materials', json={
                **self.incoming, 'id': request_id, 'invoice': 'same-invoice',
            })
            self.assertEqual(response.status_code, 201)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM incoming_materials')
            self.assertEqual(cur.fetchone()[0], 2)

    def test_consumed_receipt_and_linked_stock_cannot_be_deleted(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        self.client.post(f'/incoming_materials/{receipt}/approve', json={'approver': 'forged-name'})
        entry = self.client.get(f'/incoming_materials/{receipt}').get_json()
        self.assertEqual(entry['approved_by'], 'test')
        self.seed_indent()
        issued = self.client.post('/outgoing_materials/issue', json={
            'id': 'audit-issue', 'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material',
            'jobSpecific': False, 'issuedQty': 2, 'details': [{'id': receipt, 'consumedQty': 2}],
        })
        self.assertEqual(issued.status_code, 200, issued.get_json())
        self.assertEqual(self.client.delete(f'/incoming_materials/{receipt}').status_code, 409)
        self.assertEqual(self.client.post('/stock/delete', json={'data': {'id': receipt}}).status_code, 409)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'quantity' FROM stock")
            self.assertEqual(float(cur.fetchone()[0]), 3)

    def test_receipt_deletion_rolls_back_both_tables_on_failure(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        self.client.post(f'/incoming_materials/{receipt}/approve', json={})
        with self.conn:
            with self.conn.cursor() as cur:
                cur.execute("""CREATE FUNCTION pg_temp.reject_receipt_delete() RETURNS trigger
                               LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test rollback'; END $$""")
                cur.execute('CREATE TRIGGER reject_delete BEFORE DELETE ON incoming_materials '
                            'FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_receipt_delete()')
        with self.assertLogs(app.app.logger, level='ERROR'):
            response = self.client.delete(f'/incoming_materials/{receipt}')
        self.assertEqual(response.status_code, 500)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM stock')
            self.assertEqual(cur.fetchone()[0], 1)
            cur.execute('SELECT count(*) FROM incoming_materials')
            self.assertEqual(cur.fetchone()[0], 1)

    def test_approved_receipt_cannot_be_edited(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        self.client.post(f'/incoming_materials/{receipt}/approve', json={})
        self.assertEqual(self.client.put(f'/incoming_materials/{receipt}', json={'quantity': 8}).status_code, 409)

    def test_receipt_permission_checks_and_admin_approval(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        other = authenticated_client(app.app, 'other', 'user')
        self.assertEqual(other.put(f'/incoming_materials/{receipt}', json={'quantity': 8}).status_code, 403)
        self.assertEqual(other.delete(f'/incoming_materials/{receipt}').status_code, 403)
        self.assertEqual(other.post(f'/incoming_materials/{receipt}/approve', json={}).status_code, 403)
        self.assertEqual(other.post('/materials', json={'type': 'X', 'subtype': 'Y'}).status_code, 403)

    def test_auto_numbering_and_request_retry(self):
        original = {'serialNo': 'TRFD0001', 'jobType': 'New', '_autoNumber': True,
                    '_requestId': 'job-request-one', 'purchaserName': 'First'}
        first = self.client.post('/jobs', json=original)
        second = self.client.post('/jobs', json={**original, '_requestId': 'job-request-two'})
        retry = self.client.post('/jobs', json=original)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 201)
        self.assertEqual(first.get_json()['serialNo'], 'TRFD0001')
        self.assertEqual(second.get_json()['serialNo'], 'TRFD0002')
        self.assertEqual(retry.get_json()['serialNo'], 'TRFD0001')
        self.assertEqual(self.client.post('/jobs', json={**original, 'purchaserName': 'Changed'}).status_code, 409)

    def test_job_revision_prevents_stale_edit(self):
        self.client.post('/jobs', json={'serialNo': 'AUDIT-JOB', 'purchaserName': 'First'})
        job = self.client.get('/jobs').get_json()[0]
        self.assertEqual(self.client.put('/jobs', json={**job, 'isFinal': True}).status_code, 200)
        self.assertEqual(self.client.put('/jobs', json={**job, 'isFinal': False}).status_code, 409)
        latest = self.client.get('/jobs').get_json()[0]
        self.assertTrue(latest['isFinal'])
        self.assertEqual(latest['createdBy'], 'test')

    def test_indent_edit_preserves_issuance_and_rejects_reduction_below_issued(self):
        self.seed_indent()
        with self.conn:
            with self.conn.cursor() as cur:
                cur.execute("UPDATE job_indents SET data = data || '{\"issuedQty\":4,\"issuedValue\":40}'")
                cur.execute("UPDATE indent_stock SET data = '{\"indentQuantity\":6}'")
        body = {'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material', 'quantity': 20}
        self.assertEqual(self.client.post('/job_indents/update_existing', json=body).status_code, 200)
        self.assertEqual(self.client.post('/job_indents/update_existing', json={**body, 'quantity': 3}).status_code, 409)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'indentQuantity' FROM indent_stock")
            self.assertEqual(float(cur.fetchone()[0]), 16)
            cur.execute('SELECT data FROM job_indents')
            row = cur.fetchone()[0]
            self.assertEqual(row['quantity'], 20)
            self.assertEqual(row['issuedQty'], 4)

    def test_job_specific_catalog_definition_does_not_require_job_number(self):
        body = {'type': 'Audit', 'subtype': 'Specific', 'jobSpecific': True, 'unit': 'Kgs'}
        self.assertEqual(self.client.post('/materials', json=body).status_code, 201)
        self.assertEqual(self.client.post('/materials', json=body).status_code, 201)
        self.assertEqual(self.client.post('/materials', json={**body, 'unit': 'Nos'}).status_code, 409)

    def test_report_retry_and_owner_checked_delete(self):
        body = {'data': {'_requestId': 'report-one', 'savedBy': 'forged-name', 'serialNo': 'AUDIT-JOB'}}
        for _ in range(2):
            self.assertEqual(self.client.post('/reports', json=body).status_code, 201)
        with self.conn.cursor() as cur:
            cur.execute("SELECT count(*), min(data->>'savedBy') FROM reports")
            self.assertEqual(cur.fetchone(), (1, 'test'))
        other = authenticated_client(app.app, 'other', 'user')
        reference = {'_requestId': 'report-one', 'savedBy': 'test'}
        self.assertEqual(other.delete('/reports', json=reference).status_code, 403)
        self.assertEqual(self.client.delete('/reports', json=reference).status_code, 200)

    def test_stock_edit_rejects_stale_expected_balance(self):
        with self.conn:
            with self.conn.cursor() as cur:
                cur.execute('INSERT INTO stock VALUES (%s,%s,%s)', (
                    'manual-lot', 'Audit - Material', Json({'quantity': 5, 'price': 10}),
                ))
        body = {'data': {'id': 'manual-lot'}, 'quantity': 6, 'price': 12,
                'editFlag': True, 'expectedQuantity': 5, 'expectedPrice': 10}
        self.assertEqual(self.client.post('/stock/update', json=body).status_code, 200)
        self.assertEqual(self.client.post('/stock/update', json=body).status_code, 409)
        with self.conn.cursor() as cur:
            cur.execute('SELECT data FROM stock')
            self.assertEqual(cur.fetchone()[0]['quantity'], 6)

    def test_login_issues_signed_token_and_bad_tokens_are_rejected(self):
        with self.conn:
            with self.conn.cursor() as cur:
                cur.execute('INSERT INTO users VALUES (%s,%s,%s)', (
                    'login-test', bcrypt.hashpw(b'password', bcrypt.gensalt(rounds=4)).decode(), 'user',
                ))
        response = self.client.post('/users/login', json={'username': 'login-test', 'password': 'password'})
        self.assertEqual(response.status_code, 200)
        user = response.get_json()
        self.assertNotIn('password', user)
        self.assertEqual(verify_token(app.app.config['SECRET_KEY'], 'Bearer ' + user['token'])['username'], 'login-test')
        self.assertEqual(self.client.get('/jobs', headers={'Authorization': 'Bearer forged'}).status_code, 401)
        self.assertEqual(self.client.post('/users/login', json={'username': 'login-test', 'password': 'wrong'}).status_code, 401)


if __name__ == '__main__':
    unittest.main()
