"""Transactional writes. Callers own commit/rollback and connection lifetime."""
import hashlib
import json
import math
import uuid
from datetime import datetime, timezone

from psycopg2.extras import Json


class WriteError(ValueError):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def payload_object(value):
    if not isinstance(value, dict) or not value:
        raise WriteError('A nonempty JSON object is required')
    return dict(value)


def number(value, label, positive=False):
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        raise WriteError(f'Invalid {label}')
    if isinstance(value, bool) or not math.isfinite(parsed) or (parsed <= 0 if positive else parsed < 0):
        raise WriteError(f'Invalid {label}')
    return parsed


def identity(data):
    if any(not isinstance(data.get(key), str) or not data[key].strip()
           for key in ('type', 'subtype')):
        raise WriteError('Material type and subtype are required')
    if data.get('jobSpecific') is True and not data.get('serialNo'):
        raise WriteError('Job number is required for job-specific material')
    return f"{data['type']} - {data['subtype']}" + (
        f" - {data['serialNo']}" if data.get('jobSpecific') is True else ''
    )


def fingerprint(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def lock(cur, key):
    cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))', (key,))


def owner_or_admin(user, owner):
    if user['role'] != 'admin' and user['username'] != owner:
        raise WriteError('Only the creator or an administrator can change this record', 403)


def create_receipt(conn, payload, user):
    data = payload_object(payload)
    identity(data)
    number(data.get('quantity'), 'quantity', positive=True)
    number(data.get('price'), 'price')
    operation = data.get('id')
    if not isinstance(operation, str) or not operation.strip() or len(operation) > 128:
        raise WriteError('A stable incoming request id is required; update the application', 409)
    data = {key: value for key, value in data.items()
            if key not in ('approved', 'approved_by', 'approved_at')}
    data['user'] = user['username']
    with conn.cursor() as cur:
        lock(cur, f'incoming:{operation}')
        cur.execute('SELECT data FROM incoming_materials WHERE id = %s', (operation,))
        row = cur.fetchone()
        if row:
            previous = {key: value for key, value in row[0].items()
                        if key not in ('approved', 'approved_by', 'approved_at')}
            if previous != data:
                raise WriteError('Incoming request id was already used for different data', 409)
            return {'id': operation, 'message': 'Incoming material already submitted'}
        data.update(approved=False, approved_by=None, approved_at=None)
        cur.execute('INSERT INTO incoming_materials (id, data) VALUES (%s, %s)', (operation, Json(data)))
    return {'id': operation, 'message': 'Incoming material submitted'}


def edit_receipt(conn, entry_id, payload, user):
    data = payload_object(payload)
    with conn.cursor() as cur:
        cur.execute('SELECT data FROM incoming_materials WHERE id = %s FOR UPDATE', (entry_id,))
        row = cur.fetchone()
        if not row:
            raise WriteError('Incoming entry not found', 404)
        entry = row[0]
        owner_or_admin(user, entry.get('user'))
        if entry.get('approved'):
            raise WriteError('Cannot edit an approved entry', 409)
        entry.update({key: value for key, value in data.items()
                      if key not in ('id', 'user', 'entryDate', 'approved', 'approved_by', 'approved_at')})
        identity(entry)
        number(entry.get('quantity'), 'quantity', positive=True)
        number(entry.get('price'), 'price')
        cur.execute('UPDATE incoming_materials SET data = %s WHERE id = %s', (Json(entry), entry_id))
    return {'message': 'Entry updated'}


def _has_issues(cur, stock_ids):
    cur.execute("""SELECT 1 FROM outgoing_materials o
                   WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(
                       COALESCE(o.data->'details', '[]'::jsonb)) d
                       WHERE d->>'id' = ANY(%s)) LIMIT 1""", (stock_ids,))
    return cur.fetchone() is not None


def delete_receipt(conn, entry_id, user):
    with conn.cursor() as cur:
        cur.execute('SELECT data FROM incoming_materials WHERE id = %s FOR UPDATE', (entry_id,))
        row = cur.fetchone()
        if not row:
            raise WriteError('Incoming entry not found', 404)
        entry = row[0]
        owner_or_admin(user, entry.get('user'))
        # Include legacy lots only when the complete source identity matches.
        if entry.get('approved') and user['role'] != 'admin':
            raise WriteError('Administrator access is required to delete approved receipts', 403)
        cur.execute("""SELECT id, data FROM stock WHERE id = %s
                       OR data->>'incomingEntryId' = %s
                       OR (data->>'entryDate' = %s AND data->>'type' = %s
                           AND data->>'subtype' = %s AND data->>'user' = %s)
                       ORDER BY id FOR UPDATE""", (
            entry_id, entry_id, entry.get('entryDate'), entry.get('type'),
            entry.get('subtype'), entry.get('user'),
        ))
        lots = cur.fetchall()
        if entry.get('approved') and len(lots) != 1:
            raise WriteError('Approved receipt has missing or ambiguous stock; reconcile it first', 409)
        if not entry.get('approved') and lots:
            raise WriteError('Unapproved receipt unexpectedly has stock; reconcile it first', 409)
        if lots:
            lot_ids = [row[0] for row in lots]
            historical_ids = list({*lot_ids, entry_id, *[lot.get('id', lot_id) for lot_id, lot in lots]})
            if (_has_issues(cur, historical_ids)
                    or any(number(lot['quantity'], 'stock quantity') != number(entry['quantity'], 'receipt quantity')
                           for _, lot in lots)):
                raise WriteError('Cannot delete a receipt after stock was consumed or adjusted', 409)
            cur.execute('DELETE FROM stock WHERE id = ANY(%s)', (lot_ids,))
        cur.execute('DELETE FROM incoming_materials WHERE id = %s', (entry_id,))
    return {'message': 'Incoming entry and unused stock deleted'}


def delete_stock(conn, payload):
    data = payload_object(payload)
    stock_id = data.get('id')
    if not stock_id:
        raise WriteError('A stock row id is required')
    with conn.cursor() as cur:
        cur.execute('SELECT data FROM stock WHERE id = %s FOR UPDATE', (stock_id,))
        row = cur.fetchone()
        if not row:
            raise WriteError('Stock row not found', 404)
        if row[0].get('incomingEntryId') or row[0].get('approved') is True:
            raise WriteError('Delete the incoming receipt to remove its unused stock atomically', 409)
        if _has_issues(cur, [stock_id]):
            raise WriteError('Cannot delete a stock lot with issuance history', 409)
        cur.execute('DELETE FROM stock WHERE id = %s', (stock_id,))
    return {'message': 'Unused stock lot deleted'}


def create_job(conn, payload, user):
    data = payload_object(payload)
    auto_number = data.pop('_autoNumber', False)
    request_id = data.get('_requestId')
    digest = fingerprint(data)
    with conn.cursor() as cur:
        cur.execute('LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE')
        if request_id:
            cur.execute("SELECT serial_no, data FROM jobs WHERE data->>'_requestId' = %s", (request_id,))
            row = cur.fetchone()
            if row:
                if row[1].get('_createFingerprint') != digest or row[1].get('createdBy') != user['username']:
                    raise WriteError('Job request id was already used for different data', 409)
                return {'serialNo': row[0], 'message': 'Job already created'}
        if auto_number:
            if data.get('jobType') not in ('New', 'Repair') or not request_id:
                raise WriteError('Job type and request id are required for automatic numbering')
            prefix = 'TRFD' if data['jobType'] == 'New' else 'TRFR'
            cur.execute('SELECT COALESCE(max(substring(serial_no FROM 5)::bigint), 0) FROM jobs '
                        'WHERE serial_no ~ %s', (f'^{prefix}[0-9]+$',))
            data['serialNo'] = prefix + str(cur.fetchone()[0] + 1).zfill(4)
        serial = data.get('serialNo')
        if not isinstance(serial, str) or not serial.strip():
            raise WriteError('Job number is required')
        cur.execute('SELECT data FROM jobs WHERE serial_no = %s', (serial,))
        if cur.fetchone():
            raise WriteError('Job number already exists; refresh and use a new number', 409)
        data.update(createdBy=user['username'], _revision=1, _createFingerprint=digest)
        cur.execute('INSERT INTO jobs (serial_no, data) VALUES (%s, %s)', (serial, Json(data)))
    return {'serialNo': serial, 'message': 'Job created'}


def update_job(conn, payload):
    data = payload_object(payload)
    serial = data.get('serialNo')
    with conn.cursor() as cur:
        cur.execute('SELECT data FROM jobs WHERE serial_no = %s FOR UPDATE', (serial,))
        row = cur.fetchone()
        if not row:
            raise WriteError('Job not found', 404)
        previous = row[0]
        if data.get('_revision', 0) != previous.get('_revision', 0):
            raise WriteError('This job changed since it was loaded; refresh before saving', 409)
        protected = ('createdBy', 'entryDateTime', '_requestId', '_createFingerprint')
        for key in protected:
            if key in previous:
                data[key] = previous[key]
            else:
                data.pop(key, None)
        data['_revision'] = previous.get('_revision', 0) + 1
        cur.execute('UPDATE jobs SET data = %s WHERE serial_no = %s', (Json(data), serial))
    return {'message': 'Job updated', 'revision': data['_revision']}


def save_material(conn, payload):
    data = payload_object(payload)
    key = identity({**data, 'jobSpecific': False})
    with conn.cursor() as cur:
        lock(cur, f'material:{key}')
        cur.execute('SELECT id, data FROM materials WHERE type = %s AND subtype = %s',
                    (data['type'], data['subtype']))
        rows = cur.fetchall()
        if rows:
            if len(rows) == 1 and {k: v for k, v in rows[0][1].items() if k != 'id'} == {
                    k: v for k, v in data.items() if k != 'id'}:
                return {'id': rows[0][0], 'message': 'Material already exists'}
            raise WriteError('Material type/subtype already exists', 409)
        material_id = str(uuid.uuid4())
        cur.execute('INSERT INTO materials (id, type, subtype, data) VALUES (%s, %s, %s, %s)',
                    (material_id, data['type'], data['subtype'], Json(data)))
    return {'id': material_id, 'message': 'Material created'}


def edit_indent(conn, payload):
    data = payload_object(payload)
    quantity = number(data.get('quantity'), 'indent quantity', positive=True)
    if not data.get('serialNo'):
        raise WriteError('Job number is required')
    identity(data)
    with conn.cursor() as cur:
        cur.execute("""SELECT id, data FROM job_indents WHERE jobid = %s
                       AND data->>'type' = %s AND data->>'subtype' = %s
                       ORDER BY id FOR UPDATE""", (data['serialNo'], data['type'], data['subtype']))
        rows = cur.fetchall()
        if len(rows) != 1:
            raise WriteError('Exactly one matching indent is required; refresh or reconcile duplicates', 409)
        row_id, entry = rows[0]
        issued = number(entry.get('issuedQty') or 0, 'issued quantity')
        if quantity * 1.02 + 1e-8 < issued:
            raise WriteError('New indent quantity is below quantities already issued', 409)
        old = number(entry.get('quantity'), 'previous indent quantity', positive=True)
        key = identity(entry)
        cur.execute('SELECT data FROM indent_stock WHERE key = %s FOR UPDATE', (key,))
        aggregate_row = cur.fetchone()
        if not aggregate_row:
            raise WriteError('Outstanding indent total is missing; reconcile it before editing', 409)
        aggregate = aggregate_row[0]
        total = number(aggregate.get('indentQuantity'), 'outstanding total') + quantity - old
        if total < -1e-8:
            raise WriteError('Outstanding indent total is inconsistent; reconcile it before editing', 409)
        aggregate['indentQuantity'] = max(0, total)
        entry['quantity'] = quantity
        entry['description'] = data.get('description', entry.get('description', ''))
        cur.execute('UPDATE job_indents SET data = %s WHERE id = %s', (Json(entry), row_id))
        cur.execute('UPDATE indent_stock SET data = %s WHERE key = %s', (Json(aggregate), key))
    return {'message': 'Job indent and outstanding total updated'}


def save_report(conn, payload, user):
    outer = payload_object(payload)
    data = payload_object(outer.get('data'))
    data['savedBy'] = user['username']
    operation = data.get('_requestId')
    if not isinstance(operation, str) or not operation:
        raise WriteError('A stable report request id is required; update the application', 409)
    with conn.cursor() as cur:
        lock(cur, f'report:{operation}')
        cur.execute("SELECT data FROM reports WHERE data->>'_requestId' = %s", (operation,))
        row = cur.fetchone()
        if row:
            if row[0] != data:
                raise WriteError('Report request id was already used for different data', 409)
            return {'message': 'Report already saved'}
        cur.execute('INSERT INTO reports (data) VALUES (%s)', (Json(data),))
    return {'message': 'Report saved'}


def delete_report(conn, payload, user):
    data = payload_object(payload)
    owner = data.get('savedBy')
    owner_or_admin(user, owner)
    with conn.cursor() as cur:
        if data.get('_requestId'):
            cur.execute("DELETE FROM reports WHERE data->>'_requestId' = %s AND data->>'savedBy' = %s",
                        (data['_requestId'], owner))
        elif owner and data.get('timestamp'):
            cur.execute("DELETE FROM reports WHERE data->>'savedBy' = %s AND data->>'timestamp' = %s",
                        (owner, data['timestamp']))
        else:
            raise WriteError('Report identity is required')
        if cur.rowcount == 0:
            raise WriteError('Report not found', 404)
    return {'message': 'Report deleted'}
