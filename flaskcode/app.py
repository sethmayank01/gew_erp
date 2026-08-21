from flask import Flask, request, jsonify
from flask_cors import CORS
import psycopg2
import psycopg2.extras
from psycopg2 import sql
import bcrypt
import json
import uuid
import os
import sys

app = Flask(__name__)
CORS(app)

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

    data = request.json
    username = data.get('username')
    password = data.get('password')

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

    data = request.json.get('data')

    if not data:
        return jsonify({
            'error': 'Missing report data'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO reports (data)
            VALUES (%s)
            ''',
            (
                jsonb(data),
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Report saved'
        }), 201

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


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
def delete_report():

    data = request.get_json(silent=True)

    if not data:
        return jsonify({
            'error': 'Missing data'
        }), 400

    saved_by = data.get('savedBy')
    timestamp = data.get('timestamp')

    if not saved_by or not timestamp:
        return jsonify({
            'error': 'Missing savedBy or timestamp'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            DELETE FROM reports
            WHERE data->>'savedBy' = %s
              AND data->>'timestamp' = %s
            ''',
            (
                saved_by,
                timestamp
            )
        )

        deleted_count = cur.rowcount

        conn.commit()

        cur.close()
        conn.close()

        if deleted_count > 0:

            return jsonify({
                'message': 'Report deleted'
            }), 200

        else:

            return jsonify({
                'message': 'Report not found'
            }), 404

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# JOBS
# ============================================================

@app.route('/jobs', methods=['POST'])
def save_job():

    job = request.json

    if not job:
        return jsonify({
            'error': 'Missing job data'
        }), 400

    serialNo = job.get('serialNo')

    if not serialNo:
        return jsonify({
            'error': 'serialNo is required'
        }), 401

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO jobs
                (serial_no, data)
            VALUES
                (%s, %s)
            ON CONFLICT (serial_no)
            DO UPDATE SET
                data = EXCLUDED.data
            ''',
            (
                serialNo,
                jsonb(job)
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Job saved/updated'
        }), 201

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


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

    data = request.json

    if not data:
        return jsonify({
            'error': 'Missing material data'
        }), 400

    material_id = str(uuid.uuid4())

    m_type = data.get('type')
    subtype = data.get('subtype')

    if not m_type or not subtype:
        return jsonify({
            'error': 'type and subtype are required'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO materials
                (id, type, subtype, data)
            VALUES
                (%s, %s, %s, %s)
            ON CONFLICT (id)
            DO UPDATE SET
                data = EXCLUDED.data
            ''',
            (
                material_id,
                m_type,
                subtype,
                jsonb(data)
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Material added/updated',
            'id': material_id
        }), 201

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


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

    data = request.json

    if not data:
        return jsonify({
            'error': 'Missing incoming material data'
        }), 400

    incoming_id = str(uuid.uuid4())

    data['approved'] = False
    data['approved_by'] = None
    data['approved_at'] = None

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO incoming_materials
                (id, data)
            VALUES
                (%s, %s)
            ''',
            (
                incoming_id,
                jsonb(data)
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Incoming material submitted',
            'id': incoming_id
        }), 201

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/incoming_materials/<entry_id>/approve', methods=['POST'])
def approve_material_entry(entry_id):

    data = request.json or {}
    approver = data.get('approver')

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
            ''',
            (entry_id,)
        )

        row = cur.fetchone()

        if not row:
            return jsonify({
                'error': 'Entry not found'
            }), 404

        entry = parse_json_data(row[0])

        # ---------------------------------------------------------
        # 2. Check whether already approved
        # ---------------------------------------------------------
        if entry.get('approved', False):
            return jsonify({
                'error': 'Already approved'
            }), 400

        # ---------------------------------------------------------
        # 3. Prepare approval information
        # ---------------------------------------------------------
        entry['approved'] = True
        entry['approved_by'] = approver

        # Keep this if your incoming data already has it
        # entry['approved_at'] = datetime.now().isoformat()

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
        stock_id = str(uuid.uuid4())

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
        # Every incoming lot remains a separate row for LIFO.
        # ---------------------------------------------------------
        cur.execute(
            '''
            INSERT INTO stock (id, key, data)
            VALUES (%s, %s, %s)
            ''',
            (
                stock_id,
                key,
                jsonb(entry)
            )
        )

        # ---------------------------------------------------------
        # 8. Commit BOTH operations together
        # ---------------------------------------------------------
        conn.commit()

        return jsonify({
            'message': 'Entry approved and added to stock'
        }), 200

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

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            DELETE FROM incoming_materials
            WHERE id = %s
            ''',
            (entry_id,)
        )

        if cur.rowcount == 0:

            cur.close()
            conn.close()

            return jsonify({
                'error': 'Entry not found'
            }), 404

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Entry deleted'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


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

    """
    Update a material incoming entry before approval.
    Only allowed if not approved.
    """

    data = request.json

    if not data:
        return jsonify({
            'error': 'Missing updated data'
        }), 400

    try:

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

        if not row:

            cur.close()
            conn.close()

            return jsonify({
                'error': 'Entry not found'
            }), 404

        entry = parse_json_data(row[0])

        if entry.get('approved', False):

            cur.close()
            conn.close()

            return jsonify({
                'error': 'Cannot edit an approved entry'
            }), 400

        for key, value in data.items():

            if key not in [
                'id',
                'approved',
                'approved_by',
                'approved_at'
            ]:
                entry[key] = value

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

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Entry updated'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# OUTGOING MATERIALS
# ============================================================

@app.route('/outgoing_materials', methods=['POST'])
def submit_material_outgoing():

    data = request.json

    if not data:
        return jsonify({
            'error': 'Missing outgoing material data'
        }), 400

    outgoing_id = str(uuid.uuid4())

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            INSERT INTO outgoing_materials
                (id, data)
            VALUES
                (%s, %s)
            ''',
            (
                outgoing_id,
                jsonb(data)
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Outgoing material submitted',
            'id': outgoing_id
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


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

    data = request.json.get('data')

    if not data:
        return jsonify({
            'error': 'Missing stock data'
        }), 400

    stock_id = str(uuid.uuid4())

    job_specific = data.get(
        'jobSpecific',
        False
    )

    serial_no = data.get(
        'serialNo',
        None
    )

    m_type = data.get(
        'type',
        None
    )

    subtype = data.get(
        'subtype',
        None
    )

    material = f"{m_type} - {subtype}"

    key = material

    print(
        "key %s, job_specific %s ",
        key,
        job_specific
    )

    if job_specific and serial_no:

        key = f"{material} - {serial_no}"

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        print(
            "add_stock() INSERT INTO stock "
            "(id,key,data) VALUES (%s,%s,%s)",
            (
                stock_id,
                key,
                data
            )
        )

        cur.execute(
            '''
            INSERT INTO stock
                (id, key, data)
            VALUES
                (%s, %s, %s)
            ''',
            (
                stock_id,
                key,
                jsonb(data)
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Stock Added'
        }), 200

    except Exception as e:

        print(
            "Exception: %s",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/stock/delete', methods=['POST'])
def delete_stock_entry():

    try:

        payload = request.json.get('data')

        print(
            "Payload: %s",
            payload
        )

        m_type = payload.get('type')
        subtype = payload.get('subtype')
        serial_no = payload.get('serialNo', None)
        is_job_specific = payload.get('jobSpecific')

        if not m_type or not subtype:

            return jsonify({
                'error': 'Missing type or subtype'
            }), 401

        key = f"{m_type} - {subtype}"

        if is_job_specific and serial_no:

            key = f"{key} - {serial_no}"

        invoice = payload.get('invoice')

        if not key or not invoice:

            return jsonify({
                'error': 'Missing key or invoice'
            }), 400

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            SELECT *
            FROM stock
            WHERE key = %s
              AND data->>'invoice' = %s
            ''',
            (
                key,
                invoice
            )
        )

        result = cur.fetchone()

        if not result:

            conn.close()

            return jsonify({
                'error': 'No matching record found'
            }), 404

        cur.execute(
            '''
            DELETE FROM stock
            WHERE key = %s
              AND data->>'invoice' = %s
            ''',
            (
                key,
                invoice
            )
        )

        conn.commit()

        conn.close()

        return jsonify({
            'message': 'Entry deleted successfully'
        }), 200

    except Exception as e:

        print(
            "Exception: %s",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


@app.route('/stock/update', methods=['POST'])
def update_stock():

    data = request.json.get('data')
    issue_quantity = request.json.get('quantity')
    updated_price = request.json.get('price')
    edit_stock = request.json.get('editFlag')

    if not data and issue_quantity:

        return jsonify({
            'error': 'Missing stock data or quantity'
        }), 400

    material = data.get('material')

    if not material:

        return jsonify({
            'error': 'material field required'
        }), 401

    job_specific = data.get(
        'jobSpecific',
        False
    )

    serial_no = data.get(
        'serialNo',
        None
    )

    invoice = data.get(
        'invoice',
        None
    )

    key = material

    if job_specific and serial_no:

        key = f"{material} - {serial_no}"

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            SELECT id, data
            FROM stock
            WHERE key = %s
              AND data->>'invoice' = %s
            ''',
            (
                key,
                invoice
            )
        )

        row = cur.fetchone()

        if row:

            existing_data = parse_json_data(
                row[1]
            )

        else:

            existing_data = None

        if existing_data is None:

            return jsonify({
                'error': 'Stock entry not found'
            }), 404

        # ----------------------------------------------------
        # Update current stock quantity
        # ----------------------------------------------------

        if edit_stock != True:

            current_qty = parse_float(
                existing_data.get(
                    'quantity',
                    0.0
                )
            )

            new_qty = max(
                0.0,
                current_qty -
                parse_float(issue_quantity)
            )

            existing_data['quantity'] = new_qty

        else:

            existing_data['quantity'] = parse_float(
                issue_quantity
            )

            existing_data['price'] = parse_float(
                updated_price
            )

        print(
            "STOCK %s New Quantity %s",
            existing_data,
            parse_float(issue_quantity)
        )

        cur.execute(
            '''
            UPDATE stock
            SET data = %s
            WHERE key = %s
              AND data->>'invoice' = %s
            ''',
            (
                jsonb(existing_data),
                key,
                invoice
            )
        )

        # ----------------------------------------------------
        # Update indent stock
        # ----------------------------------------------------

        if edit_stock != True:

            cur.execute(
                '''
                SELECT data
                FROM indent_stock
                WHERE key = %s
                ''',
                (key,)
            )

            indentrow = cur.fetchone()

            if indentrow:

                indentrow = parse_json_data(
                    indentrow[0]
                )

            else:

                indentrow = None

            if indentrow is not None:

                print(
                    "INDENT STOCK %s,%s",
                    indentrow,
                    issue_quantity,
                    key
                )

                if float(
                    indentrow.get(
                        'indentQuantity',
                        0.0
                    )
                ) > 0.0:

                    indentrow['indentQuantity'] = (
                        float(
                            indentrow.get(
                                'indentQuantity',
                                0.0
                            )
                        )
                        -
                        float(issue_quantity)
                    )

                cur.execute(
                    '''
                    UPDATE indent_stock
                    SET data = %s
                    WHERE key = %s
                    ''',
                    (
                        jsonb(indentrow),
                        key
                    )
                )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Stock updated'
        }), 200

    except Exception as e:

        exc_type, exc_obj, tb = sys.exc_info()

        line_number = tb.tb_lineno

        print(
            f"Exception: {e} at line {line_number}"
        )

        return jsonify({
            'error': str(e)
        }), 500


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
            SELECT key, data
            FROM stock
            ORDER BY key
            '''
        )

        rows = cur.fetchall()

        cur.close()
        conn.close()

        stock_list = []

        for row in rows:

            key = row[0]

            data = parse_json_data(
                row[1]
            )

            if not isinstance(data, dict):
                continue

            data['key'] = key

            # Existing application logic:
            #
            # General stock:
            #     no serialNo
            #
            # Job-specific stock:
            #     serialNo exists

            has_serial_no = (
                'serialNo' in data
            )

            if has_serial_no == is_job_specific:

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

    stock_data = request.json.get(
        'stockData'
    )

    is_job_specific = request.json.get(
        'isJobSpecific',
        False
    )

    if (
        not stock_data
        or not isinstance(stock_data, list)
    ):

        return jsonify({
            'error': 'stockData must be a list'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        for item in stock_data:

            m_type = item.get('type')
            subtype = item.get('subtype')
            serial_no = item.get(
                'serialNo',
                None
            )

            if not m_type or not subtype:
                continue

            key = f"{m_type} - {subtype}"

            if is_job_specific and serial_no:

                key = f"{key} - {serial_no}"

            cur.execute(
                '''
                INSERT INTO stock
                    (key, data)
                VALUES
                    (%s, %s)
                ON CONFLICT (key)
                DO UPDATE SET
                    data = EXCLUDED.data
                ''',
                (
                    key,
                    jsonb(item)
                )
            )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Stock saved'
        }), 200

    except Exception as e:

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# JOB INDENTS
# ============================================================

@app.route('/job_indents', methods=['POST'])
def submit_job_indent():

    data = request.json.get(
        'data'
    )

    if (
        not data
        or not isinstance(data, list)
    ):

        return jsonify({
            'error': 'List of indents expected'
        }), 400

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        for indent in data:

            jobid = indent.get(
                'serialNo'
            )

            matType = indent.get(
                'type'
            )

            subType = indent.get(
                'subtype'
            )

            job_specific = (
                indent.get(
                    'jobSpecific'
                ) is True
            )

            indentquantity = indent.get(
                'quantity'
            )

            if not jobid:
                continue

            if job_specific:

                stock_key = (
                    f"{matType} - "
                    f"{subType} - "
                    f"{jobid}"
                )

            else:

                stock_key = (
                    f"{matType} - "
                    f"{subType}"
                )

            # ------------------------------------------------
            # Fetch indent stock
            # ------------------------------------------------

            cur.execute(
                '''
                SELECT data
                FROM indent_stock
                WHERE key = %s
                ''',
                (stock_key,)
            )

            row = cur.fetchone()

            if row:

                stock_data = parse_json_data(
                    row[0]
                )

                existingindentQty = stock_data[
                    "indentQuantity"
                ]

                stock_data[
                    "indentQuantity"
                ] = (
                    existingindentQty
                    +
                    indentquantity
                )

                cur.execute(
                    '''
                    UPDATE indent_stock
                    SET data = %s
                    WHERE key = %s
                    ''',
                    (
                        jsonb(stock_data),
                        stock_key
                    )
                )

            else:

                stock_data = {
                    "indentQuantity":
                        indentquantity
                }

                cur.execute(
                    '''
                    INSERT INTO indent_stock
                        (key, data)
                    VALUES
                        (%s, %s)
                    ''',
                    (
                        stock_key,
                        jsonb(stock_data)
                    )
                )

            # ------------------------------------------------
            # Save job indent
            # ------------------------------------------------

            cur.execute(
                '''
                INSERT INTO job_indents
                    (jobid, data)
                VALUES
                    (%s, %s)
                ''',
                (
                    jobid,
                    jsonb(indent)
                )
            )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Job indents submitted'
        }), 200

    except Exception as e:

        print(
            "Exception: %s",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


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

    data = request.json

    if not data:

        return jsonify({
            'error': 'Missing indent data'
        }), 400

    jobid = data.get(
        'serialNo'
    )

    item_type = data.get(
        'type'
    )

    item_subtype = data.get(
        'subtype'
    )

    if not jobid:

        return jsonify({
            'error': 'serialNo is required'
        }), 401

    if not item_type or not item_subtype:

        return jsonify({
            'error': 'type and subtype are required'
        }), 402

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        # JSONB operators directly.
        # No data::json conversion required.

        cur.execute(
            '''
            SELECT *
            FROM job_indents
            WHERE jobid = %s
              AND data->>'type' = %s
              AND data->>'subtype' = %s
            ''',
            (
                jobid,
                item_type,
                item_subtype
            )
        )

        row = cur.fetchone()

        if not row:

            return jsonify({
                'error':
                'Indent with matching jobid, '
                'type, and subtype not found'
            }), 400

        indent_id = row[0]

        matched_indent = parse_json_data(
            row[2]
        )

        old_issued_qty = float(
            matched_indent.get(
                'issuedQty'
            ) or 0
        )

        old_issued_value = float(
            matched_indent.get(
                'issuedValue'
            ) or 0
        )

        new_issued_qty = float(
            data.get(
                'issuedQty'
            ) or 0
        )

        new_issued_value = float(
            data.get(
                'issuedValue'
            ) or 0
        )

        total_issued_qty = (
            old_issued_qty
            +
            new_issued_qty
        )

        total_issued_value = (
            old_issued_value
            +
            new_issued_value
        )

        matched_indent['price'] = data.get(
            'price'
        )

        matched_indent['issuedQty'] = (
            total_issued_qty
        )

        matched_indent['issuedValue'] = (
            total_issued_value
        )

        matched_indent['jobSpecific'] = data.get(
            'jobSpecific'
        )

        matched_indent['user_out'] = data.get(
            'user_out'
        )

        matched_indent['out_time'] = data.get(
            'out_time'
        )

        cur.execute(
            '''
            UPDATE job_indents
            SET data = %s
            WHERE id = %s
            ''',
            (
                jsonb(matched_indent),
                indent_id
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Job indent updated'
        }), 200

    except Exception as e:

        print(
            "Exception:",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


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

    data = request.json

    if not data:

        return jsonify({
            'error': 'Missing indent data'
        }), 400

    jobid = data.get(
        'serialNo'
    )

    item_type = data.get(
        'type'
    )

    item_subtype = data.get(
        'subtype'
    )

    if not jobid:

        return jsonify({
            'error': 'serialNo is required'
        }), 401

    if not item_type or not item_subtype:

        return jsonify({
            'error': 'type and subtype are required'
        }), 402

    try:

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute(
            '''
            SELECT *
            FROM job_indents
            WHERE jobid = %s
              AND data->>'type' = %s
              AND data->>'subtype' = %s
            ''',
            (
                jobid,
                item_type,
                item_subtype
            )
        )

        row = cur.fetchone()

        if not row:

            return jsonify({
                'error':
                'Indent with matching jobid, '
                'type, and subtype not found'
            }), 400

        indent_id = row[0]

        matched_indent = parse_json_data(
            row[2]
        )

        matched_indent['quantity'] = data.get(
            'quantity'
        )

        cur.execute(
            '''
            UPDATE job_indents
            SET data = %s
            WHERE id = %s
            ''',
            (
                jsonb(matched_indent),
                indent_id
            )
        )

        conn.commit()

        cur.close()
        conn.close()

        return jsonify({
            'message': 'Job indent updated'
        }), 200

    except Exception as e:

        print(
            "Exception: %s",
            str(e)
        )

        return jsonify({
            'error': str(e)
        }), 500


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route('/health', methods=['GET'])
def health():

    return jsonify({
        'status': 'OK'
    })


# ============================================================
# START SERVER
# ============================================================

if __name__ == '__main__':

    app.run(
        host='0.0.0.0',
        port=5005,
        debug=True
    )