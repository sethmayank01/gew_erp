from flask import Flask, request, jsonify, g
from flask_cors import CORS
import psycopg2
import psycopg2.extras
from psycopg2 import sql
import bcrypt
import json
import uuid
import os
import sys
import secrets
from datetime import datetime, timezone
from stock_issue import IssueError, issue_material, update_stock_lot
from indent_submission import IndentSubmissionError, submit_indents
from authentication import AuthenticationError, issue_token, verify_token
import write_safety

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('GEW_ERP_SECRET_KEY') or secrets.token_hex(32)
CORS(app)


@app.before_request
def authenticate_request():
    if request.method == 'OPTIONS' or request.endpoint in (None, 'login', 'health'):
        return None
    try:
        g.user = verify_token(app.config['SECRET_KEY'], request.headers.get('Authorization'))
    except AuthenticationError as error:
        return jsonify({'error': str(error)}), 401
    admin_endpoints = {
        'add_user', 'reset_password', 'delete_user', 'get_users',
        'add_material', 'delete_material', 'approve_material_entry',
        'update_existing_job_indent', 'update_job_record', 'update_stock',
        'delete_stock_entry', 'add_stock', 'save_stock',
    }
    if request.endpoint in admin_endpoints and g.user['role'] != 'admin':
        return jsonify({'error': 'Administrator access is required'}), 403


def _write_transaction(action, *args, status=200):
    conn = None
    try:
        conn = get_db_connection()
        with conn:
            result = action(conn, *args)
        return jsonify(result), status
    except write_safety.WriteError as error:
        return jsonify({'error': str(error)}), error.status
    except Exception:
        app.logger.exception('Database write failed')
        return jsonify({'error': 'Database write failed; refresh or retry the same operation'}), 500
    finally:
        if conn is not None:
            conn.close()

# ============================================================
# DATABASE CONNECTION SETUP
# ============================================================

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'gew_erp')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASS = os.getenv('DB_PASS', 'gew@1973')
DB_PORT = os.getenv('DB_PORT', 5432)


def get_db_connection():
    conn = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        port=DB_PORT
    )
    return conn


# ============================================================
# JSONB HELPERS
# ============================================================

def jsonb(value):
    """
    Convert a Python dict/list into a PostgreSQL JSONB parameter.

    Use this instead of json.dumps() when writing JSONB columns.
    """
    return psycopg2.extras.Json(value)


def parse_json_data(value):
    """
    PostgreSQL JSONB is normally returned by psycopg2
    as a Python dict/list.

    Older TEXT/JSON rows may be returned as a string.

    This helper supports both.
    """
    if value is None:
        return {}

    if isinstance(value, (dict, list)):
        return value

    if isinstance(value, str):
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return {}

    return {}


def parse_float(value, default=0.0):
    try:
        if value is None:
            return default

        return float(
            str(value)
            .replace(',', '')
            .strip()
        )

    except (ValueError, TypeError):
        return default


# ============================================================
# USERS
# ============================================================

@app.route('/users/login', methods=['POST'])
def login():

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({'error': 'Login data must be a JSON object'}), 400
    username = data.get('username')
    password = data.get('password')
    if not isinstance(username, str) or not isinstance(password, str) or not username or not password:
        return jsonify({'error': 'Username and password are required'}), 400

    conn = get_db_connection()
    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )

    cur.execute(
        'SELECT * FROM users WHERE username = %s',
        (username,)
    )

    user = cur.fetchone()

    cur.close()
    conn.close()

    if not user:
        return jsonify({
            'error': 'Invalid username or password'
        }), 401

    hashed_password = user['password'].encode('utf-8')

    if bcrypt.checkpw(
        password.encode('utf-8'),
        hashed_password
    ):

        user_dict = dict(user)
        user_dict.pop('password')
        user_dict['token'] = issue_token(app.config['SECRET_KEY'], user['username'], user['role'])

        return jsonify(user_dict)

    else:

        return jsonify({
            'error': 'Invalid username or password'
        }), 401


@app.route('/users', methods=['POST'])
def add_user():

    data = request.json

    username = data.get('username')
    password = data.get('password')
    role = data.get('role')

    if not all([username, password, role]):
        return jsonify({
            'error': 'Missing fields'
        }), 400

    hashed = bcrypt.hashpw(
        password.encode('utf-8'),
        bcrypt.gensalt()
    )

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO users
                (username, password, role)
            VALUES
                (%s, %s, %s)
            ON CONFLICT (username)
            DO UPDATE SET
                password = EXCLUDED.password,
                role = EXCLUDED.role
            ''',
            (
                username,
                hashed.decode('utf-8'),
                role
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'User added/updated'
        }), 201

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/users/reset_password', methods=['PUT'])
def reset_password():

    data = request.json

    username = data.get('username')
    new_password = data.get('newPassword')

    if not all([username, new_password]):
        return jsonify({
            'error': 'Missing fields'
        }), 400

    hashed = bcrypt.hashpw(
        new_password.encode('utf-8'),
        bcrypt.gensalt()
    )

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            UPDATE users
            SET password = %s
            WHERE username = %s
            ''',
            (
                hashed.decode('utf-8'),
                username
            )
        )

        if cur.rowcount == 0:

            cur.close()
            conn.close()

            return jsonify({
                'error': 'User not found'
            }), 404

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Password updated'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/users/<username>', methods=['DELETE'])
def delete_user(username):

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            'DELETE FROM users WHERE username = %s',
            (username,)
        )

        if cur.rowcount == 0:

            cur.close()
            conn.close()

            return jsonify({
                'error': 'User not found'
            }), 404

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'User deleted'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/users', methods=['GET'])
def get_users():

    conn = get_db_connection()

    cur = conn.cursor(
        cursor_factory=psycopg2.extras.DictCursor
    )

    cur.execute(
        'SELECT username, role FROM users ORDER BY username'
    )

    users = cur.fetchall()

    cur.close()
    conn.close()

    users_list = [
        {
            'username': u['username'],
            'role': u['role']
        }
        for u in users
    ]

    return jsonify(users_list)


# ============================================================
# REPORTS
# ============================================================

@app.route('/reports', methods=['POST'])
def save_report():
    return _write_transaction(write_safety.save_report, request.get_json(silent=True), g.user, status=201)


@app.route('/reports', methods=['GET'])
def get_reports():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        'SELECT data FROM reports ORDER BY id DESC'
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    reports = [
        parse_json_data(row[0])
        for row in rows
    ]

    return jsonify(reports)


@app.route('/reports', methods=['DELETE'])
@app.route('/reports/delete', methods=['POST'])
def delete_report():
    return _write_transaction(write_safety.delete_report, request.get_json(silent=True), g.user)


# ============================================================
# JOBS
# ============================================================

@app.route('/jobs', methods=['POST'])
def save_job():
    return _write_transaction(write_safety.create_job, request.get_json(silent=True), g.user, status=201)


@app.route('/jobs', methods=['GET'])
def get_jobs():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        'SELECT data FROM jobs ORDER BY serial_no'
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    jobs = [
        parse_json_data(row[0])
        for row in rows
    ]

    return jsonify(jobs)


@app.route('/jobs', methods=['PUT'])
def update_job_record():
    return _write_transaction(write_safety.update_job, request.get_json(silent=True))


@app.route('/jobs/open', methods=['GET'])
def get_open_jobs():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        'SELECT data FROM jobs ORDER BY serial_no'
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    jobs_list = [
        parse_json_data(row[0])
        for row in rows
    ]

    open_jobs = [
        job
        for job in jobs_list
        if not job.get('isFinal', False)
    ]

    return jsonify(open_jobs)


# ============================================================
# MATERIALS
# ============================================================

@app.route('/materials', methods=['POST'])
def add_material():
    return _write_transaction(write_safety.save_material, request.get_json(silent=True), status=201)


@app.route('/materials', methods=['GET'])
def get_materials():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        'SELECT data FROM materials ORDER BY id'
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    materials = [
        parse_json_data(row[0])
        for row in rows
    ]

    return jsonify(materials)


@app.route('/materials', methods=['DELETE'])
def delete_material():

    data = request.json

    m_type = data.get('type')
    subtype = data.get('subtype')

    if not m_type or not subtype:
        return jsonify({
            'error': 'type and subtype required'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            DELETE FROM materials
            WHERE type = %s
              AND subtype = %s
            ''',
            (
                m_type,
                subtype
            )
        )

        if cur.rowcount == 0:

            cur.close()
            conn.close()

            return jsonify({
                'error': 'Material not found'
            }), 404

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Material deleted'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# INCOMING MATERIALS
# ============================================================

@app.route('/incoming_materials', methods=['POST'])
def submit_material_incoming():
    return _write_transaction(write_safety.create_receipt, request.get_json(silent=True), g.user, status=201)


@app.route('/incoming_materials/<entry_id>/approve', methods=['POST'])
def approve_material_entry(entry_id):

    data = request.json or {}
    approver = g.user['username']

    if not approver:
        return jsonify({
            'error': 'Approver is required'
        }), 400

    conn = None
    cur = None

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # ---------------------------------------------------------
        # 1. Get incoming entry
        # ---------------------------------------------------------
        cur.execute(
            '''
            SELECT data
            FROM incoming_materials
            WHERE id = %s
            FOR UPDATE
            ''',
            (entry_id,)
        )

        row = cur.fetchone()

        if not row:
            return jsonify({
                'error': 'Entry not found'
            }), 404

        entry = parse_json_data(row[0])

        write_safety.identity(entry)
        write_safety.number(entry.get('quantity'), 'quantity', positive=True)
        write_safety.number(entry.get('price'), 'price')

        # ---------------------------------------------------------
        # 2. Check whether already approved
        # ---------------------------------------------------------
        if entry.get('approved', False):
            return jsonify({
                'message': 'Entry already approved; stock unchanged'
            }), 200

        # ---------------------------------------------------------
        # 3. Prepare approval information
        # ---------------------------------------------------------
        entry['approved'] = True
        entry['approved_by'] = approver
        entry['approved_at'] = datetime.now(timezone.utc).isoformat()

        # ---------------------------------------------------------
        # 4. Build stock key
        # ---------------------------------------------------------
        m_type = entry.get('type')
        subtype = entry.get('subtype')
        job_specific = entry.get('jobSpecific', False)
        serial_no = entry.get('serialNo')

        if not m_type or not subtype:
            return jsonify({
                'error': 'Incoming entry is missing type or subtype'
            }), 400

        key = f"{m_type} - {subtype}"

        if job_specific and serial_no:
            key = f"{key} - {serial_no}"

        # ---------------------------------------------------------
        # 5. Create stock ID
        # ---------------------------------------------------------
        # Reuse the incoming ID so the stock primary key is also an
        # idempotency key for this approval.
        stock_id = entry_id
        stock_data = dict(entry)
        stock_data['incomingEntryId'] = entry_id

        # ---------------------------------------------------------
        # 6. Update incoming entry as approved
        # ---------------------------------------------------------
        cur.execute(
            '''
            UPDATE incoming_materials
            SET data = %s
            WHERE id = %s
            ''',
            (
                jsonb(entry),
                entry_id
            )
        )

        # ---------------------------------------------------------
        # 7. Add as a NEW stock lot
        #
        # IMPORTANT:
        # Do NOT update an existing stock row.
        # Every incoming lot remains a separate row for FIFO.
        # ---------------------------------------------------------
        cur.execute(
            '''
            INSERT INTO stock (id, key, data)
            VALUES (%s, %s, %s)
            ''',
            (
                stock_id,
                key,
                jsonb(stock_data)
            )
        )

        # ---------------------------------------------------------
        # 8. Commit BOTH operations together
        # ---------------------------------------------------------
        conn.commit()

        return jsonify({
            'message': 'Entry approved and added to stock'
        }), 200

    except write_safety.WriteError as error:
        if conn:
            conn.rollback()
        return jsonify({'error': str(error)}), error.status
    except Exception as e:

        if conn:
            conn.rollback()

        print("Exception in approve_material_entry:", str(e))

        return jsonify({
            'error': str(e)
        }), 500

    finally:

        if cur:
            cur.close()

        if conn:
            conn.close()

@app.route('/incoming_materials', methods=['GET'])
def get_material_incoming_entries():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        '''
        SELECT id, data
        FROM incoming_materials
        ORDER BY id
        '''
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    entries = []

    for row in rows:

        entry = parse_json_data(row[1])

        entry['id'] = row[0]

        entries.append(entry)

    return jsonify(entries)


@app.route('/incoming_materials/<entry_id>', methods=['DELETE'])
def delete_material_entry(entry_id):
    return _write_transaction(write_safety.delete_receipt, entry_id, g.user)


@app.route('/incoming_materials/<entry_id>', methods=['GET'])
def get_material_entry_by_id(entry_id):

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        '''
        SELECT data
        FROM incoming_materials
        WHERE id = %s
        ''',
        (entry_id,)
    )

    row = cur.fetchone()

    cur.close()
    conn.close()

    if not row:

        return jsonify({
            'error': 'Entry not found'
        }), 404

    return jsonify(
        parse_json_data(row[0])
    )


@app.route('/incoming_materials/<entry_id>', methods=['PUT'])
def update_material_incoming_entry(entry_id):
    return _write_transaction(write_safety.edit_receipt, entry_id, request.get_json(silent=True), g.user)


# ============================================================
# OUTGOING MATERIALS
# ============================================================

@app.route('/outgoing_materials/issue', methods=['POST'])
def issue_outgoing_material():
    conn = None
    try:
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            return jsonify({'error': 'Missing outgoing material data'}), 400
        data['user_out'] = g.user['username']
        conn = get_db_connection()
        with conn:
            result = issue_material(conn, data)
        return jsonify({'id': result['id'], 'message': 'Material issued'}), 200
    except (IssueError, ValueError, TypeError) as e:
        return jsonify({'error': str(e)}), 409
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        if conn is not None:
            conn.close()


@app.route('/outgoing_materials', methods=['POST'])
def submit_material_outgoing():
    return jsonify({'error': 'This legacy write is disabled; update the application and use the atomic workflow'}), 410


@app.route('/outgoing_materials', methods=['GET'])
def get_material_outgoing_entries():

    try:
        search = request.args.get('search', '').strip()

        conn = get_db_connection()
        cur = conn.cursor()

        if search:

            search_pattern = f"%{search}%"

            cur.execute("""
                SELECT id, data
                FROM outgoing_materials
                WHERE
                    data ->> 'material' ILIKE %s
                    OR data ->> 'type' ILIKE %s
                    OR data ->> 'subtype' ILIKE %s
                    OR data ->> 'serialNo' ILIKE %s
                    OR data ->> 'invoice' ILIKE %s
                    OR data ->> 'user' ILIKE %s
                    OR data ->> 'user_out' ILIKE %s
                ORDER BY (data ->> 'out_time') DESC NULLS LAST
                LIMIT 200
            """, (
                search_pattern,
                search_pattern,
                search_pattern,
                search_pattern,
                search_pattern,
                search_pattern,
                search_pattern
            ))

        else:

            cur.execute("""
                SELECT id, data
                FROM outgoing_materials
                ORDER BY (data ->> 'out_time') DESC NULLS LAST
                LIMIT 200
            """)

        rows = cur.fetchall()

        cur.close()
        conn.close()

        entries = []

        for row in rows:
            entry = parse_json_data(row[1])
            entry['id'] = row[0]
            entries.append(entry)

        return jsonify(entries)

    except Exception as e:

        print("Exception in /outgoing_materials:", str(e))

        return jsonify({
            'error': str(e)
        }), 500

# ============================================================
# STOCK
# ============================================================

@app.route('/stock/add', methods=['POST'])
def add_stock():
    return jsonify({'error': 'This legacy write is disabled; update the application and use the atomic workflow'}), 410


@app.route('/stock/delete', methods=['POST'])
def delete_stock_entry():
    payload = request.get_json(silent=True) or {}
    return _write_transaction(write_safety.delete_stock, payload.get('data'))


@app.route('/stock/update', methods=['POST'])
def update_stock():
    conn = None
    try:
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return jsonify({'error': 'Missing stock data'}), 400
        if payload.get('editFlag') is not True:
            return jsonify({'error': 'Legacy stock deductions are disabled; use atomic material issuance'}), 410
        conn = get_db_connection()
        with conn:
            update_stock_lot(conn, payload)
        return jsonify({'message': 'Stock updated'}), 200
    except (IssueError, ValueError, TypeError) as e:
        return jsonify({'error': str(e)}), 409
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        if conn is not None:
            conn.close()


@app.route('/indent_stock', methods=['GET'])
def get_indent_stock():

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        'SELECT * FROM indent_stock'
    )

    indent_stock = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify(indent_stock)


@app.route('/stock', methods=['GET'])
def get_stock():

    is_job_specific = request.args.get(
        'isJobSpecific',
        'false'
    ).lower() == 'true'

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            SELECT id, key, data
            FROM stock
            ORDER BY key
            '''
        )

        rows = cur.fetchall()

        cur.close()
        conn.close()

        stock_list = []

        for row in rows:

            stock_id = row[0]
            key = row[1]

            data = parse_json_data(
                row[2]
            )

            if not isinstance(data, dict):
                continue

            data['id'] = stock_id
            data['key'] = key

            item_is_job_specific = data.get('jobSpecific') is True

            if item_is_job_specific == is_job_specific:

                stock_list.append(data)

        return jsonify(stock_list)

    except Exception as e:

        print(
            "Exception in get_stock:",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/stock/save', methods=['POST'])
def save_stock():
    return jsonify({'error': 'This legacy write is disabled; update the application and use the atomic workflow'}), 410


# ============================================================
# JOB INDENTS
# ============================================================

@app.route('/job_indents', methods=['POST'])
def submit_job_indent():
    payload = request.get_json(silent=True)
    data = payload.get('data') if isinstance(payload, dict) else None
    if isinstance(data, list):
        data = [{**item, 'user_ind': g.user['username']} if isinstance(item, dict) else item for item in data]
    conn = None
    try:
        conn = get_db_connection()
        with conn:
            submit_indents(conn, data)
        return jsonify({'message': 'Job indents submitted'}), 200
    except IndentSubmissionError as error:
        return jsonify({'error': str(error)}), error.status_code
    except Exception as e:
        app.logger.exception('Could not submit job indents')
        return jsonify({'error': str(e)}), 500
    finally:
        if conn is not None:
            conn.close()


@app.route('/job_indents/<jobid>', methods=['GET'])
def get_indents_for_job(jobid):

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        '''
        SELECT data
        FROM job_indents
        WHERE jobid = %s
        ''',
        (jobid,)
    )

    rows = cur.fetchall()

    cur.close()
    conn.close()

    indents = [
        parse_json_data(row[0])
        for row in rows
    ]

    return jsonify(indents)


@app.route('/job_indents', methods=['PUT'])
def update_job_indent():
    return jsonify({'error': 'This legacy write is disabled; update the application and use the atomic workflow'}), 410


# ============================================================
# OPEN JOB INDENTS
# ============================================================

@app.route('/open_job_indents', methods=['GET'])
def get_open_job_indents():

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        # Same logic currently used by /jobs/open

        cur.execute(
            '''
            SELECT serial_no, data
            FROM jobs
            ORDER BY serial_no
            '''
        )

        job_rows = cur.fetchall()

        open_jobs = []

        for row in job_rows:

            job_data = parse_json_data(
                row[1]
            )

            if not job_data.get(
                'isFinal',
                False
            ):

                open_jobs.append({
                    'serialNo': row[0],
                    'data': job_data
                })

        if not open_jobs:

            cur.close()
            conn.close()

            return jsonify([])

        job_ids = [
            j['serialNo']
            for j in open_jobs
        ]

        # ONE query for all indents

        cur.execute(
            '''
            SELECT jobid, data
            FROM job_indents
            WHERE jobid = ANY(%s)
            ''',
            (job_ids,)
        )

        indent_rows = cur.fetchall()

        indent_map = {}

        for row in indent_rows:

            jobid = row[0]

            if jobid not in indent_map:

                indent_map[jobid] = []

            indent_map[jobid].append(
                parse_json_data(
                    row[1]
                )
            )

        result = []

        for job in open_jobs:

            job_data = job['data']

            job_no = job['serialNo']

            result.append({
                'serialNo': job_no,
                'purchaserName':
                    job_data.get(
                        'purchaserName',
                        ''
                    ),
                'kVA':
                    job_data.get(
                        'kva',
                        ''
                    ),
                'tappingType':
                    job_data.get(
                        'tappingType',
                        ''
                    ),
                'hvVoltage':
                    job_data.get(
                        'hvVoltage',
                        ''
                    ),
                'lvVoltage':
                    job_data.get(
                        'lvVoltage',
                        ''
                    ),
                'entries':
                    indent_map.get(
                        job_no,
                        []
                    )
            })

        cur.close()
        conn.close()

        return jsonify(result)

    except Exception as e:

        print(
            "Exception in /open_job_indents:",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# UPDATE EXISTING JOB INDENT
# ============================================================

@app.route('/job_indents/update_existing', methods=['POST'])
def update_existing_job_indent():
    return _write_transaction(write_safety.edit_indent, request.get_json(silent=True))


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route('/health', methods=['GET'])
def health():

    return jsonify({
        'status': 'OK',
        'version': '1.2.10'
    })


# ============================================================
# START SERVER
# ============================================================

if __name__ == '__main__':

    app.run(
        host='0.0.0.0',
        port=5005,
        debug=False
    )
