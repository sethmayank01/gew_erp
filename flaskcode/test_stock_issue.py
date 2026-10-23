"""PostgreSQL regression tests using temporary tables, never production rows."""
import os
import unittest
from unittest.mock import patch

import psycopg2
from psycopg2.extras import Json
import app
from stock_issue import IssueError, issue_material


class StockIssueTests(unittest.TestCase):
    def setUp(self):
        self.conn = psycopg2.connect(host=os.environ['ERP_TEST_DB_HOST'], database=app.DB_NAME,
                                     user=app.DB_USER, password=app.DB_PASS, connect_timeout=5)
        with self.conn.cursor() as cur:
            cur.execute('CREATE TEMP TABLE stock (id text PRIMARY KEY, key text, data jsonb)')
            cur.execute('CREATE TEMP TABLE outgoing_materials (id text PRIMARY KEY, data jsonb)')
            cur.execute('CREATE TEMP TABLE job_indents (id integer PRIMARY KEY, jobid text, data jsonb)')
            cur.execute('CREATE TEMP TABLE indent_stock (key text PRIMARY KEY, data jsonb)')
            for row_id in ('lot-a', 'lot-b'):
                cur.execute('INSERT INTO stock VALUES (%s, %s, %s)', (row_id, 'OLTC - EO16', Json({
                    'id': 'shared-incoming-id', 'type': 'OLTC', 'subtype': 'EO16',
                    'material': 'OLTC - EO16', 'invoice': '3868', 'quantity': 1,
                    'price': 225000, 'jobSpecific': False})))
            cur.execute('INSERT INTO job_indents VALUES (1, %s, %s)', ('TEST-JOB', Json({
                'type': 'OLTC', 'subtype': 'EO16', 'quantity': 2, 'issuedQty': 0, 'issuedValue': 0})))
            cur.execute('INSERT INTO indent_stock VALUES (%s, %s)', ('OLTC - EO16', Json({'indentQuantity': 2})))
        self.conn.commit()
        self.request = {'id': 'test-issue', 'serialNo': 'TEST-JOB', 'type': 'OLTC',
                        'subtype': 'EO16', 'issuedQty': 1, 'jobSpecific': False,
                        'details': [{'id': 'lot-a', 'consumedQty': 1}],
                        'issuedValue': 1, 'out_time': '2026-10-09T12:00:00', 'user_out': 'test'}

    def tearDown(self):
        self.conn.close()

    def quantities(self):
        with self.conn.cursor() as cur:
            cur.execute("SELECT id, (data->>'quantity')::numeric FROM stock ORDER BY id")
            return dict(cur.fetchall())

    def test_same_invoice_deducts_only_selected_row_and_retry_is_idempotent(self):
        with self.conn:
            result = issue_material(self.conn, self.request)
        self.assertEqual(result['issuedValue'], 225000)
        with self.conn:
            issue_material(self.conn, self.request)
        self.assertEqual(self.quantities(), {'lot-a': 0, 'lot-b': 1})
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM outgoing_materials')
            self.assertEqual(cur.fetchone()[0], 1)
            cur.execute("SELECT data->>'issuedQty' FROM job_indents")
            self.assertEqual(float(cur.fetchone()[0]), 1)

    def test_insert_failure_rolls_back_stock_and_indent(self):
        with self.conn.cursor() as cur:
            cur.execute("ALTER TABLE outgoing_materials ADD CHECK (id <> 'test-issue')")
        self.conn.commit()
        with self.assertRaises(psycopg2.IntegrityError):
            with self.conn:
                issue_material(self.conn, self.request)
        self.assertEqual(self.quantities(), {'lot-a': 1, 'lot-b': 1})
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'issuedQty' FROM job_indents")
            self.assertEqual(float(cur.fetchone()[0]), 0)

    def test_insufficient_stock_and_duplicate_allocations_are_rejected(self):
        for details in ([{'id': 'lot-a', 'consumedQty': 2}],
                        [{'id': 'lot-a', 'consumedQty': .5}, {'id': 'lot-a', 'consumedQty': .5}]):
            with self.assertRaises(IssueError):
                with self.conn:
                    issue_material(self.conn, {**self.request, 'issuedQty': sum(d['consumedQty'] for d in details),
                                               'details': details})
        self.assertEqual(self.quantities(), {'lot-a': 1, 'lot-b': 1})

    def test_old_build_uses_primary_ids_and_only_one_lot_is_updated(self):
        # Closing is owned by tearDown while Flask owns each transaction.
        class ConnectionProxy:
            def __init__(self, conn):
                self.conn = conn
            def __getattr__(self, name):
                return getattr(self.conn, name)
            def __enter__(self):
                return self.conn.__enter__()
            def __exit__(self, *args):
                return self.conn.__exit__(*args)
            def close(self):
                pass
        with patch.object(app, 'get_db_connection', return_value=ConnectionProxy(self.conn)):
            client = app.app.test_client()
            stocks = client.get('/stock?isJobSpecific=false').get_json()
            self.assertEqual({s['id'] for s in stocks}, {'lot-a', 'lot-b'})
            response = client.post('/stock/update', json={'data': stocks[0], 'quantity': 1,
                                                         'price': 0, 'editFlag': False})
            self.assertEqual(response.status_code, 200, response.get_json())
            self.assertEqual(sum(self.quantities().values()), 1)
            response = client.post('/stock/update', json={'data': stocks[0], 'quantity': 1,
                                                         'price': 0, 'editFlag': False})
            self.assertEqual(response.status_code, 409)


if __name__ == '__main__':
    unittest.main()
