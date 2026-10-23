"""Known unsafe write paths: expected failures reproduce audit findings.

Only connection-local temporary tables are used. Remove an expectedFailure
decorator when fixing its corresponding safety invariant.
"""
import os
import unittest
from unittest.mock import patch

import psycopg2
from psycopg2.extras import Json

import app


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
        self.client = app.app.test_client()
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

    @unittest.expectedFailure
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

    @unittest.expectedFailure
    def test_new_job_creation_must_not_silently_overwrite_an_existing_job(self):
        for customer in ('First customer', 'Second customer'):
            response = self.client.post('/jobs', json={
                'serialNo': 'AUDIT-JOB', 'jobType': 'New', 'purchaserName': customer,
            })
            self.assertEqual(response.status_code, 201)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'purchaserName' FROM jobs WHERE serial_no = 'AUDIT-JOB'")
            self.assertEqual(cur.fetchone()[0], 'First customer', 'Original job was overwritten')

    @unittest.expectedFailure
    def test_indent_edit_must_update_outstanding_aggregate(self):
        self.seed_indent()
        response = self.client.post('/job_indents/update_existing', json={
            'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material', 'quantity': 20,
        })
        self.assertEqual(response.status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'indentQuantity' FROM indent_stock")
            self.assertEqual(float(cur.fetchone()[0]), 20, 'Aggregate stayed at 10')

    @unittest.expectedFailure
    def test_legacy_issue_update_retry_must_not_double_issued_quantity(self):
        self.seed_indent()
        payload = {'serialNo': 'AUDIT-JOB', 'type': 'Audit', 'subtype': 'Material',
                   'issuedQty': 2, 'issuedValue': 20, 'out_time': 'same-operation'}
        for _ in range(2):
            self.assertEqual(self.client.put('/job_indents', json=payload).status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'issuedQty' FROM job_indents")
            self.assertEqual(float(cur.fetchone()[0]), 2, 'Retry increased issued quantity to 4')

    @unittest.expectedFailure
    def test_material_retry_must_not_create_duplicate_catalog_entries(self):
        for _ in range(2):
            response = self.client.post('/materials', json={'type': 'Audit', 'subtype': 'Material'})
            self.assertEqual(response.status_code, 201)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM materials')
            self.assertEqual(cur.fetchone()[0], 1, 'Created two identical material definitions')

    @unittest.expectedFailure
    def test_deleting_receipt_must_not_leave_its_approved_stock_orphaned(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        self.assertEqual(self.client.post(
            f'/incoming_materials/{receipt}/approve', json={'approver': 'audit-test'},
        ).status_code, 200)
        self.assertEqual(self.client.delete(f'/incoming_materials/{receipt}').status_code, 200)
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM stock')
            self.assertEqual(cur.fetchone()[0], 0, 'Receipt deleted but its approved stock remains')

    @unittest.expectedFailure
    def test_approval_must_require_authenticated_approver(self):
        receipt = self.client.post('/incoming_materials', json=self.incoming).get_json()['id']
        response = self.client.post(
            f'/incoming_materials/{receipt}/approve', json={'approver': 'someone-else'},
        )
        self.assertIn(response.status_code, (401, 403), 'Approval succeeded without login')

    @unittest.expectedFailure
    def test_report_delete_url_used_by_app_must_exist(self):
        response = self.client.post('/reports/delete', json={
            'savedBy': 'audit-test', 'timestamp': '2026-10-23T12:00:00',
        })
        self.assertNotEqual(response.status_code, 404, 'The app calls a nonexistent endpoint')


if __name__ == '__main__':
    unittest.main()
