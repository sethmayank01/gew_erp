"""Regression tests use only connection-local temporary tables."""
import copy
import os
import unittest
from unittest.mock import patch

import psycopg2

import app
from indent_submission import IndentSubmissionError, submit_indents
from test_support import authenticated_client


class IndentSubmissionTests(unittest.TestCase):
    def setUp(self):
        self.conn = psycopg2.connect(
            host=os.environ['ERP_TEST_DB_HOST'], database=app.DB_NAME,
            user=app.DB_USER, password=app.DB_PASS, connect_timeout=5,
        )
        with self.conn.cursor() as cur:
            cur.execute('CREATE TEMP TABLE job_indents (id serial PRIMARY KEY, jobid text, data jsonb)')
            cur.execute('CREATE TEMP TABLE indent_stock (key text PRIMARY KEY, data jsonb)')
        self.conn.commit()
        self.batch = [
            {'serialNo': 'TEST-INDENT', 'type': 'Paint', 'subtype': subtype,
             'quantity': quantity, 'jobSpecific': False, 'user_ind': 'test'}
            for subtype, quantity in [('White', 3), ('7035', 7), ('Thinner', 3)]
        ]

    def tearDown(self):
        self.conn.close()

    def totals(self):
        with self.conn.cursor() as cur:
            cur.execute('SELECT key, data FROM indent_stock ORDER BY key')
            return {key: data['indentQuantity'] for key, data in cur.fetchall()}

    def count(self):
        with self.conn.cursor() as cur:
            cur.execute('SELECT count(*) FROM job_indents')
            return cur.fetchone()[0]

    def test_repeated_three_item_submission_does_not_duplicate_rows_or_totals(self):
        with self.conn:
            submit_indents(self.conn, self.batch)
        before = self.totals()
        retry = copy.deepcopy(self.batch)
        for item in retry:
            item['ind_time'] = 'different client timestamp'
        with self.assertRaises(IndentSubmissionError) as error:
            with self.conn:
                submit_indents(self.conn, retry)
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(self.count(), 3)
        self.assertEqual(self.totals(), before)

    def test_duplicate_material_in_batch_is_rejected_before_any_write(self):
        with self.assertRaises(IndentSubmissionError):
            with self.conn:
                submit_indents(self.conn, [self.batch[0], self.batch[0]])
        self.assertEqual(self.count(), 0)
        self.assertEqual(self.totals(), {})

    def test_existing_material_rejects_entire_mixed_batch(self):
        with self.conn:
            submit_indents(self.conn, [self.batch[-1]])
        with self.assertRaises(IndentSubmissionError):
            with self.conn:
                submit_indents(self.conn, self.batch)
        self.assertEqual(self.count(), 1)
        self.assertEqual(self.totals(), {'Paint - Thinner': 3})

    def test_database_failure_rolls_back_all_rows_and_aggregate_updates(self):
        with self.conn.cursor() as cur:
            cur.execute("ALTER TABLE job_indents ADD CHECK (data->>'subtype' <> 'White')")
        self.conn.commit()
        with self.assertRaises(psycopg2.IntegrityError):
            with self.conn:
                submit_indents(self.conn, self.batch)
        self.assertEqual(self.count(), 0)
        self.assertEqual(self.totals(), {})

    def test_different_jobs_can_indent_same_material_and_keep_aggregate_metadata(self):
        with self.conn.cursor() as cur:
            cur.execute("INSERT INTO indent_stock VALUES ('Paint - White', "
                        "'{\"indentQuantity\": 2, \"note\": \"preserve\"}')")
        self.conn.commit()
        with self.conn:
            submit_indents(self.conn, [self.batch[0]])
            submit_indents(self.conn, [{**self.batch[0], 'serialNo': 'OTHER-TEST-JOB'}])
        self.assertEqual(self.totals(), {'Paint - White': 8})
        with self.conn.cursor() as cur:
            cur.execute("SELECT data->>'note' FROM indent_stock")
            self.assertEqual(cur.fetchone()[0], 'preserve')

    def test_job_specific_stock_key_is_preserved(self):
        with self.conn:
            submit_indents(self.conn, [{**self.batch[0], 'jobSpecific': True}])
        self.assertEqual(self.totals(), {'Paint - White - TEST-INDENT': 3})

    def test_invalid_payloads_are_rejected_without_writes(self):
        invalid = [None, [], {}, [None], [{}]]
        invalid += [[{**self.batch[0], 'quantity': value}]
                    for value in [None, True, 0, -1, 'nan', 'inf', 'invalid']]
        for payload in invalid:
            with self.subTest(payload=payload):
                with self.assertRaises(IndentSubmissionError):
                    with self.conn:
                        submit_indents(self.conn, payload)
        self.assertEqual(self.count(), 0)
        self.assertEqual(self.totals(), {})

    def test_http_endpoint_returns_conflict_for_old_client_retry(self):
        class ConnectionProxy:
            def __getattr__(inner, name):
                return getattr(self.conn, name)

            def __enter__(inner):
                return self.conn.__enter__()

            def __exit__(inner, *args):
                return self.conn.__exit__(*args)

            def close(inner):
                pass

        with patch.object(app, 'get_db_connection', return_value=ConnectionProxy()):
            client = authenticated_client(app.app)
            self.assertEqual(client.post('/job_indents', json={'data': self.batch}).status_code, 200)
            retry = client.post('/job_indents', json={'data': self.batch})
            self.assertEqual(retry.status_code, 409)
            self.assertIn('already exists', retry.get_json()['error'])
            self.assertEqual(self.count(), 3)


if __name__ == '__main__':
    unittest.main()
