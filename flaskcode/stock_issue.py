import math
from datetime import datetime, timedelta, timezone
from psycopg2.extras import Json


class IssueError(ValueError):
    pass


_RECEIPT_TIMEZONE = timezone(timedelta(hours=5, minutes=30))


def _fifo_key(row):
    stock_id, _, stock = row
    try:
        date = datetime.fromisoformat(str(stock.get('entryDate') or '').strip())
        if date.tzinfo is None:
            date = date.replace(tzinfo=_RECEIPT_TIMEZONE)
        return (False, date, stock_id)
    except ValueError:
        return (True, datetime.max.replace(tzinfo=timezone.utc), stock_id)


def _same_allocations(left, right):
    return left.keys() == right.keys() and all(
        math.isclose(take, right[stock_id], rel_tol=0, abs_tol=1e-8)
        for stock_id, take in left.items())


def update_stock_lot(conn, payload):
    data = payload.get('data') or {}
    stock_id = data.get('id')
    quantity = float(payload.get('quantity'))
    editing = payload.get('editFlag') is True
    if not stock_id or not math.isfinite(quantity) or quantity < 0:
        raise IssueError('A stock row id and finite nonnegative quantity are required')
    with conn.cursor() as cur:
        cur.execute('SELECT key, data FROM stock WHERE id = %s FOR UPDATE', (stock_id,))
        row = cur.fetchone()
        if not row:
            raise IssueError('Stock row not found; refresh stock before issuing')
        key, stock = row
        available = float(stock.get('quantity') or 0)
        if editing:
            expected_quantity = float(payload.get('expectedQuantity'))
            expected_price = float(payload.get('expectedPrice'))
            if (not math.isfinite(expected_quantity) or not math.isfinite(expected_price)
                    or not math.isclose(available, expected_quantity, abs_tol=1e-8)
                    or not math.isclose(float(stock.get('price') or 0), expected_price, abs_tol=1e-8)):
                raise IssueError('Stock changed since it was loaded; refresh before editing')
        if not editing and (not math.isfinite(available) or quantity > available):
            raise IssueError('Insufficient stock; refresh stock before issuing')
        stock['quantity'] = quantity if editing else available - quantity
        if editing:
            price = float(payload.get('price'))
            if not math.isfinite(price) or price < 0:
                raise IssueError('Invalid stock price')
            stock['price'] = price
        cur.execute('UPDATE stock SET data = %s WHERE id = %s', (Json(stock), stock_id))
        if not editing:
            cur.execute('SELECT data FROM indent_stock WHERE key = %s FOR UPDATE', (key,))
            row = cur.fetchone()
            if row:
                aggregate = row[0]
                aggregate['indentQuantity'] = max(0, float(aggregate.get('indentQuantity') or 0) - quantity)
                cur.execute('UPDATE indent_stock SET data = %s WHERE key = %s', (Json(aggregate), key))


def issue_material(conn, data):
    """Caller owns the transaction; inventory writes use stock primary keys."""
    issue_id = data.get('id')
    if not issue_id or not all(data.get(k) for k in ('serialNo', 'type', 'subtype')):
        raise IssueError('id, serialNo, type and subtype are required')
    quantity = float(data.get('issuedQty') or 0)
    if not math.isfinite(quantity) or quantity <= 0:
        raise IssueError('Issue quantity must be finite and positive')
    allocations = {}
    for detail in data.get('details', []):
        stock_id = detail.get('id')
        take = float(detail.get('consumedQty') or 0)
        if not stock_id or stock_id in allocations or not math.isfinite(take) or take <= 0:
            raise IssueError('Allocations require unique stock row ids and positive quantities')
        allocations[stock_id] = take
    if not allocations or not math.isclose(sum(allocations.values()), quantity, rel_tol=0, abs_tol=1e-8):
        raise IssueError('Stock allocations must equal issued quantity')
    with conn.cursor() as cur:
        # Serialize retries even before the outgoing row exists.
        cur.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))', (issue_id,))
        cur.execute('SELECT data FROM outgoing_materials WHERE id = %s', (issue_id,))
        row = cur.fetchone()
        if row:
            previous = row[0]
            keys = ('serialNo', 'type', 'subtype', 'jobSpecific', 'issuedQty')
            lots = {d['id']: float(d['consumedQty']) for d in previous['details']}
            if any(previous.get(k) != data.get(k) for k in keys) or not _same_allocations(lots, allocations):
                raise IssueError('Issue id already used for a different request')
            return previous
        cur.execute('''SELECT id, data FROM job_indents WHERE jobid = %s
                       AND data->>'type' = %s AND data->>'subtype' = %s
                       ORDER BY id FOR UPDATE''', (data['serialNo'], data['type'], data['subtype']))
        indents = cur.fetchall()
        if len(indents) != 1:
            raise IssueError('Exactly one matching job indent is required')
        indent_id, indent = indents[0]
        if float(indent.get('issuedQty') or 0) + quantity > float(indent['quantity']) * 1.02 + 1e-8:
            raise IssueError('Issue exceeds remaining indent quantity with 2% tolerance')
        job_specific = data.get('jobSpecific', False) is True
        # Lock matching lots in primary-key order, then allocate in receipt order.
        cur.execute("""SELECT id, key, data FROM stock
                       WHERE data->>'type' = %s AND data->>'subtype' = %s
                         AND COALESCE(data->>'jobSpecific', 'false') = %s
                         AND (NOT %s OR data->>'serialNo' = %s)
                       ORDER BY id FOR UPDATE""",
                    (data['type'], data['subtype'], str(job_specific).lower(),
                     job_specific, data['serialNo']))
        rows = sorted(cur.fetchall(), key=_fifo_key)
        consumed, value = [], 0.0
        fifo, deductions = {}, []
        remaining = quantity
        for stock_id, key, stock in rows:
            if remaining <= 0:
                break
            available = float(stock.get('quantity') or 0)
            if not math.isfinite(available):
                raise IssueError('Invalid stock balance')
            if available <= 0:
                continue
            take = min(remaining, available)
            price = float(stock.get('price') or 0)
            if not math.isfinite(price) or price < 0:
                raise IssueError('Invalid stock price')
            fifo[stock_id] = take
            deductions.append((stock_id, stock, available - take))
            remaining -= take
            consumed.append({**stock, 'id': stock_id, 'key': key,
                             'consumedQty': take, 'consumedPrice': price})
            value += take * price
        if remaining > 1e-8:
            raise IssueError('Insufficient stock; refresh stock before issuing')
        if not _same_allocations(fifo, allocations):
            raise IssueError('Stock lots must be issued oldest first (FIFO); refresh and review the allocation')
        result = {**data, 'details': consumed, 'issuedValue': value, 'weightedAvgPrice': value / quantity}
        for stock_id, stock, balance in deductions:
            stock['quantity'] = balance
            cur.execute('UPDATE stock SET data = %s WHERE id = %s', (Json(stock), stock_id))
        key = f"{data['type']} - {data['subtype']}"
        if data.get('jobSpecific', False):
            key += f" - {data['serialNo']}"
        cur.execute('SELECT data FROM indent_stock WHERE key = %s FOR UPDATE', (key,))
        row = cur.fetchone()
        if row:
            aggregate = row[0]
            aggregate['indentQuantity'] = max(0, float(aggregate.get('indentQuantity') or 0) - quantity)
            cur.execute('UPDATE indent_stock SET data = %s WHERE key = %s', (Json(aggregate), key))
        indent.update(issuedQty=float(indent.get('issuedQty') or 0) + quantity,
                      issuedValue=float(indent.get('issuedValue') or 0) + value,
                      price=value / quantity, user_out=data.get('user_out'), out_time=data.get('out_time'))
        cur.execute('UPDATE job_indents SET data = %s WHERE id = %s', (Json(indent), indent_id))
        cur.execute('INSERT INTO outgoing_materials (id, data) VALUES (%s, %s)', (issue_id, Json(result)))
        return result
