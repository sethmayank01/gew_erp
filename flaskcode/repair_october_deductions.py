"""Guarded one-time repair. Dry run by default; --apply commits the correction."""
import argparse
import copy
import json
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import Json
import app


CASES = [
    ('33c55eb5-5bfe-4a19-984e-7b265f3acfce', '2026-10-07', 'OLTC - EO16',
     '06775301-754c-4413-839b-850dece7c1ce', 'c42d04a2-63d3-40be-8dc3-f46a2da1635f'),
    ('7d616aa5-4eab-4989-89a4-bd1670432cdc', '2026-10-02', 'OCTCSwitch - 33kV_7P_100A_2deck',
     'e418bd6e-7799-4e1c-8d9e-30a8faa1b846', 'aef27a9f-fbdb-47cb-b3be-a9a817018766'),
]


def repair(host, apply):
    conn = psycopg2.connect(host=host, database=app.DB_NAME, user=app.DB_USER,
                            password=app.DB_PASS, connect_timeout=5)
    audit = []
    try:
        with conn.cursor() as cur:
            for outgoing_id, date, material, consumed_id, restored_id in CASES:
                cur.execute('SELECT data FROM outgoing_materials WHERE id = %s FOR UPDATE', (outgoing_id,))
                outgoing = cur.fetchone()[0]
                if outgoing.get('stockDeductionCorrection'):
                    audit.append({'id': outgoing_id, 'status': 'already corrected'})
                    continue
                assert outgoing['out_time'].startswith(date) and outgoing['issuedQty'] == 1
                assert outgoing['material'] == material and len(outgoing['details']) == 1
                assert outgoing['details'][0]['consumedQty'] == 1
                cur.execute('SELECT id, key, data FROM stock WHERE id = ANY(%s) ORDER BY id FOR UPDATE',
                            ([consumed_id, restored_id],))
                rows = {row[0]: (row[1], row[2]) for row in cur.fetchall()}
                assert len(rows) == 2
                cur.execute('SELECT id, data FROM stock_backup WHERE id = ANY(%s)',
                            ([consumed_id, restored_id],))
                backups = {i: app.parse_json_data(d) for i, d in cur.fetchall()}
                assert len(backups) == 2
                for row_id in rows:
                    assert rows[row_id][0] == material
                    assert float(rows[row_id][1]['quantity']) == 0
                    assert float(backups[row_id]['quantity']) == 1
                # Check that the correction agrees with the complete material ledger.
                cur.execute('''SELECT COALESCE(sum((data->>'quantity')::numeric), 0)
                               FROM incoming_materials WHERE data->>'material' = %s
                               AND data->>'approved' = 'true' ''', (material,))
                incoming_qty = float(cur.fetchone()[0])
                cur.execute('''SELECT COALESCE(sum((data->>'issuedQty')::numeric), 0)
                               FROM outgoing_materials WHERE data->>'material' = %s''', (material,))
                issued_qty = float(cur.fetchone()[0])
                cur.execute('''SELECT COALESCE(sum((data->>'quantity')::numeric), 0)
                               FROM stock WHERE key = %s''', (material,))
                stock_qty = float(cur.fetchone()[0])
                assert incoming_qty - issued_qty == stock_qty + 1, (material, incoming_qty, issued_qty, stock_qty)
                before = {i: copy.deepcopy(d) for i, (_, d) in rows.items()}
                after = copy.deepcopy(before)
                after[restored_id]['quantity'] = 1.0
                # The OCTC update copied the older lot's metadata onto the consumed lot.
                if material.startswith('OCTCSwitch'):
                    after[consumed_id] = {**backups[consumed_id], 'quantity': 0.0}
                correction = {
                    'reason': 'Legacy deduction updated all stock lots with the same material key and invoice',
                    'correctedAt': datetime.now(timezone.utc).isoformat(),
                    'consumedStockId': consumed_id, 'restoredStockId': restored_id,
                    'restoredQuantity': 1.0, 'before': before, 'after': after,
                    'ledger': {'incoming': incoming_qty, 'issued': issued_qty, 'stockAfter': stock_qty + 1},
                }
                for row_id, updated in after.items():
                    if updated != before[row_id]:
                        cur.execute('UPDATE stock SET data = %s WHERE id = %s', (Json(updated), row_id))
                        assert cur.rowcount == 1
                outgoing['stockDeductionCorrection'] = correction
                cur.execute('UPDATE outgoing_materials SET data = %s WHERE id = %s', (Json(outgoing), outgoing_id))
                audit.append({'id': outgoing_id, 'material': material, **correction})
        if apply:
            conn.commit()
        else:
            conn.rollback()
        print(json.dumps({'committed': apply, 'corrections': audit}, indent=2))
    finally:
        conn.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    repair(args.host, args.apply)
