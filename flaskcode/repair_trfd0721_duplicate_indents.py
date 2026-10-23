"""Guarded repair of the three confirmed 2026-10-23 duplicate paint indents."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path

import psycopg2
from psycopg2.extras import Json

import app


def repair(conn, apply=False):
    expected = {
        'Hot Oil_White_Single Pack': (6371, 6374, 3),
        'PU_7035': (6372, 6375, 7),
        'PU_Thiner': (6373, 6376, 3),
    }
    with conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT id, jobid, data FROM public.job_indents
                   WHERE jobid = %s AND data->>'type' = 'Paint'
                     AND data->>'subtype' = ANY(%s) ORDER BY id FOR UPDATE""",
                ('TRFD0721', list(expected)),
            )
            rows = cur.fetchall()
            expected_ids = {i for keep, duplicate, _ in expected.values() for i in (keep, duplicate)}
            if {row[0] for row in rows} != expected_ids:
                raise ValueError('The six expected rows changed or the repair was already applied')
            by_id = {row[0]: row[2] for row in rows}
            for subtype, (keep, duplicate, quantity) in expected.items():
                for row_id, timestamp in (
                    (keep, '2026-10-23 16:16:15.357744'),
                    (duplicate, '2026-10-23 16:16:15.275743'),
                ):
                    item = by_id[row_id]
                    if not (
                        item.get('serialNo') == 'TRFD0721'
                        and item.get('type') == 'Paint'
                        and item.get('subtype') == subtype
                        and float(item.get('quantity', 0)) == quantity
                        and item.get('user_ind') == 'sunil'
                        and item.get('ind_time') == timestamp
                        and item.get('jobSpecific') is False
                    ):
                        raise ValueError(f'Row {row_id} no longer matches the confirmed duplicate')
                extra = by_id[duplicate]
                if (float(extra.get('issuedQty') or 0) != 0
                        or float(extra.get('issuedValue') or 0) != 0
                        or extra.get('out_time')):
                    raise ValueError(f'Duplicate {duplicate} has issuance activity; refusing to delete')

            keys = sorted(f'Paint - {subtype}' for subtype in expected)
            cur.execute(
                'SELECT key, data FROM public.indent_stock WHERE key = ANY(%s) ORDER BY key FOR UPDATE',
                (keys,),
            )
            aggregates = dict(cur.fetchall())
            changes = {}
            for subtype, (_, _, quantity) in expected.items():
                key = f'Paint - {subtype}'
                if key not in aggregates or float(aggregates[key].get('indentQuantity') or 0) < quantity:
                    raise ValueError(f'Unexpected outstanding indent total for {key}')
                changes[key] = {
                    'before': aggregates[key]['indentQuantity'],
                    'after': float(aggregates[key]['indentQuantity']) - quantity,
                }
            print(json.dumps({'delete_ids': [6374, 6375, 6376], 'aggregate_changes': changes}, indent=2))
            if not apply:
                return

            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            backup = Path(__file__).resolve().parents[1] / 'tmp' / f'TRFD0721-indent-backup-{stamp}.json'
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_text(json.dumps({
                'job_indents': rows,
                'indent_stock_before': aggregates,
                'planned_changes': changes,
            }, indent=2), encoding='utf-8')
            print(f'Backup: {backup}')
            cur.execute('DELETE FROM public.job_indents WHERE id = ANY(%s)', ([6374, 6375, 6376],))
            if cur.rowcount != 3:
                raise ValueError('Unexpected deletion count')
            for key, change in changes.items():
                updated = {**aggregates[key], 'indentQuantity': change['after']}
                cur.execute('UPDATE public.indent_stock SET data = %s WHERE key = %s', (Json(updated), key))
                if cur.rowcount != 1:
                    raise ValueError(f'Unexpected aggregate row count for {key}')
    print('Committed: removed three duplicate unissued indents and corrected outstanding totals.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    connection = psycopg2.connect(
        host=args.host, database=app.DB_NAME, user=app.DB_USER,
        password=app.DB_PASS, connect_timeout=5,
    )
    try:
        repair(connection, apply=args.apply)
    finally:
        connection.close()
