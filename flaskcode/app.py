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

# DATABASE CONNECTION SETUP
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'gew_erp')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASS = os.getenv('DB_PASS', 'gew@1973')
DB_PORT = os.getenv('DB_PORT', 5432)

def get_db_connection():
    conn = psycopg2.connect(
        host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS, port=DB_PORT
    )
    return conn

# ---------------- USERS ----------------

@app.route('/users/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username')
    password = data.get('password')

    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur.execute('SELECT * FROM users WHERE username = %s', (username,))
    user = cur.fetchone()
    cur.close()
    conn.close()

    if not user:
        return jsonify({'error': 'Invalid username or password'}), 401

    hashed_password = user['password'].encode('utf-8')
    if bcrypt.checkpw(password.encode('utf-8'), hashed_password):
        user_dict = dict(user)
        user_dict.pop('password')  # Remove password hash before sending
        return jsonify(user_dict)
    else:
        return jsonify({'error': 'Invalid username or password'}), 401

@app.route('/users', methods=['POST'])
def add_user():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    role = data.get('role')

    if not all([username, password, role]):
        return jsonify({'error': 'Missing fields'}), 400

    hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            '''
            INSERT INTO users (username, password, role)
            VALUES (%s, %s, %s)
            ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = EXCLUDED.role
            ''',
            (username, hashed.decode('utf-8'), role)
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'User added/updated'}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users/reset_password', methods=['PUT'])
def reset_password():
    data = request.json
    username = data.get('username')
    new_password = data.get('newPassword')

    if not all([username, new_password]):
        return jsonify({'error': 'Missing fields'}), 400

    hashed = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt())

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'UPDATE users SET password = %s WHERE username = %s',
            (hashed.decode('utf-8'), username)
        )
        if cur.rowcount == 0:
            cur.close()
            conn.close()
            return jsonify({'error': 'User not found'}), 404
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Password updated'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users/<username>', methods=['DELETE'])
def delete_user(username):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('DELETE FROM users WHERE username = %s', (username,))
        if cur.rowcount == 0:
            cur.close()
            conn.close()
            return jsonify({'error': 'User not found'}), 404
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'User deleted'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/users', methods=['GET'])
def get_users():
    conn = get_db_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur.execute('SELECT username, role FROM users ORDER BY username')
    users = cur.fetchall()
    cur.close()
    conn.close()

    users_list = [{'username': u['username'], 'role': u['role']} for u in users]
    return jsonify(users_list)

# ---------------- REPORTS ----------------

@app.route('/reports', methods=['POST'])
def save_report():
    data = request.json.get('data')
    if not data:
        return jsonify({'error': 'Missing report data'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO reports (data) VALUES (%s)',
            (json.dumps(data),)
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Report saved'}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/reports', methods=['GET'])
def get_reports():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT data FROM reports ORDER BY id DESC')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    reports = [json.loads(row[0]) for row in rows]
    return jsonify(reports)

# ---------------- JOBS ----------------

@app.route('/jobs', methods=['POST'])
def save_job():
    job = request.json
    if not job:
        return jsonify({'error': 'Missing job data'}), 400

    serialNo = job.get('serialNo')
    if not serialNo:
        return jsonify({'error': 'serialNo is required'}), 401

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            '''
            INSERT INTO jobs (serial_no, data) VALUES (%s, %s)
            ON CONFLICT (serial_no) DO UPDATE SET data = EXCLUDED.data
            ''',
            (serialNo, json.dumps(job))
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Job saved/updated'}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/jobs', methods=['GET'])
def get_jobs():
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute('SELECT data FROM jobs ORDER BY serial_no')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    jobs = []
    for row in rows:
        jobs.append(json.loads(row[0]))
    
    return jsonify(jobs)

@app.route('/jobs/open', methods=['GET'])
def get_open_jobs():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT data FROM jobs ORDER BY serial_no')
    rows = cur.fetchall()
    cur.close()
    conn.close()

    # Parse JSON from the 'data' column
    jobs_list = [json.loads(row[0]) for row in rows]
    open_jobs = [job for job in jobs_list if not job.get('isFinal', False)]
    return jsonify(open_jobs)
    

# ---------------- MATERIALS ----------------

@app.route('/materials', methods=['POST'])
def add_material():
    data = request.json
    if not data:
        return jsonify({'error': 'Missing material data'}), 400

    material_id = str(uuid.uuid4())
    m_type = data.get('type')
    subtype = data.get('subtype')

    if not m_type or not subtype:
        return jsonify({'error': 'type and subtype are required'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            '''
            INSERT INTO materials (id, type, subtype, data)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data
            ''',
            (material_id, m_type, subtype, json.dumps(data))
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Material added/updated', 'id': material_id}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/materials', methods=['GET'])
def get_materials():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT data FROM materials ORDER BY id')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    materials = [json.loads(row[0]) for row in rows]
    return jsonify(materials)

@app.route('/materials', methods=['DELETE'])
def delete_material():
    data = request.json
    m_type = data.get('type')
    subtype = data.get('subtype')

    if not m_type or not subtype:
        return jsonify({'error': 'type and subtype required'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'DELETE FROM materials WHERE type = %s AND subtype = %s',
            (m_type, subtype)
        )
        if cur.rowcount == 0:
            cur.close()
            conn.close()
            return jsonify({'error': 'Material not found'}), 404
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Material deleted'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ---------------- INCOMING MATERIALS ----------------

@app.route('/incoming_materials', methods=['POST'])
def submit_material_incoming():
    data = request.json
    if not data:
        return jsonify({'error': 'Missing incoming material data'}), 400

    incoming_id = str(uuid.uuid4())
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO incoming_materials (id, data) VALUES (%s, %s)',
            (incoming_id, json.dumps(data))
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Incoming material submitted', 'id': incoming_id}), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/incoming_materials', methods=['GET'])
def get_material_incoming_entries():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT id, data FROM incoming_materials ORDER BY id')
    rows = cur.fetchall()
    cur.close()
    conn.close()

    entries = []
    for row in rows:
        entry = json.loads(row[1])
        entry['id'] = row[0]
        entries.append(entry)
    return jsonify(entries)

@app.route('/incoming_materials/<entry_id>', methods=['DELETE'])
def delete_material_entry(entry_id):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('DELETE FROM incoming_materials WHERE id = %s', (entry_id,))
        if cur.rowcount == 0:
            cur.close()
            conn.close()
            return jsonify({'error': 'Entry not found'}), 404
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Entry deleted'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/incoming_materials/<entry_id>', methods=['GET'])
def get_material_entry_by_id(entry_id):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT data FROM incoming_materials WHERE id = %s', (entry_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        return jsonify({'error': 'Entry not found'}), 404
    return jsonify(json.loads(row[0]))

@app.route('/outgoing_materials', methods=['POST'])
def submit_material_outgoing():
    data = request.json
    if not data:
        return jsonify({'error': 'Missing outgoing material data'}), 400

    outgoing_id = str(uuid.uuid4())
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO outgoing_materials (id, data) VALUES (%s, %s)',
            (outgoing_id, json.dumps(data))
        )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Outgoing material submitted', 'id': outgoing_id}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/outgoing_materials', methods=['GET'])
def get_material_outgoing_entries():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT id, data FROM outgoing_materials ORDER BY id')
    rows = cur.fetchall()
    cur.close()
    conn.close()

    entries = []
    for row in rows:
        entry = json.loads(row[1])
        entry['id'] = row[0]
        entries.append(entry)
    return jsonify(entries)


# ---------------- STOCK ----------------
def parse_float(value, default=0.0):
    try:
        if value is None:
            return default
        # Convert to string, remove commas, strip whitespace
        return float(str(value).replace(',', '').strip())
    except (ValueError, TypeError):
        return default

@app.route('/stock/add', methods=['POST'])
def add_stock():
    data = request.json.get('data')
    if not data:
        return jsonify({'error': 'Missing stock data'}), 400
    
    stock_id = str(uuid.uuid4())
    job_specific = data.get('jobSpecific', False)
    serial_no = data.get('serialNo', None)
    m_type = data.get('type', None)
    subtype = data.get('subtype', None)
    
    material = f"{m_type} - {subtype}"
    key = material
    print("key %s, job_specific %s ",key,job_specific)
    if job_specific and serial_no:
        key = f"{material} - {serial_no}"

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        print("add_stock() INSERT INTO stock (id,key, data) VALUES (%s, %s, %s)",(stock_id,key, json.dumps(data)))
        cur.execute(
            'INSERT INTO stock (id,key, data) VALUES (%s, %s, %s)',
                    (stock_id ,key, json.dumps(data))
            )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Stock Added'}), 200

    except Exception as e:
        print("Exception: %s",str(e))
        return jsonify({'error': str(e)}), 500


@app.route('/stock/delete', methods=['POST'])
def delete_stock_entry():
    try:
        payload = request.json.get('data')
        print("Payload: %s",payload);
        m_type = payload.get('type')
        subtype = payload.get('subtype')
        serial_no = payload.get('serialNo', None)
        is_job_specific = payload.get('jobSpecific')

        if not m_type or not subtype:
            return jsonify({'error': 'Missing type or subtype'}), 401

        key = f"{m_type} - {subtype}"
        if is_job_specific and serial_no:
            key = f"{key} - {serial_no}"

        invoice = payload.get('invoice')

        if not key or not invoice:
            return jsonify({'error': 'Missing key or invoice'}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Optional: Fetch and return the row before deletion (for logging or client display)
        cur.execute("""
            SELECT * FROM stock
            WHERE key = %s AND (data::json->>'invoice') = %s
        """, (key, invoice))
        result = cur.fetchone()
        if not result:
            conn.close()
            return jsonify({'error': 'No matching record found'}), 404

        # Now delete the row
        cur.execute("""
            DELETE FROM stock
            WHERE key = %s AND (data::json->>'invoice') = %s
        """, (key, invoice))
        conn.commit()
        conn.close()

        return jsonify({'message': 'Entry deleted successfully'}), 200

    except Exception as e:
        print("Exception: %s",str(e))
        return jsonify({'error': str(e)}), 500


@app.route('/stock/update', methods=['POST'])
def update_stock():
    data = request.json.get('data')
    issue_quantity = request.json.get('quantity')
    if not data and issue_quantity:
        return jsonify({'error': 'Missing stock data or quantity'}), 400

    # To keep the logic same as Dart updateStock method,
    # we will just store or update stock by key
    # and calculate new quantity and price accordingly.

    material = data.get('material')
    if not material:
        return jsonify({'error': 'material field required'}), 401

    job_specific = data.get('jobSpecific', False)
    serial_no = data.get('serialNo', None)
    invoice = data.get('invoice', None)
   
    key = material
    if job_specific and serial_no:
        key = f"{material} - {serial_no}"

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT * FROM stock
            WHERE key = %s AND (data::json->>'invoice') = %s
        """, (key, invoice))
        row = cur.fetchone()

        if row:
            existing_data = json.loads(row[1])
        else:
            existing_data = None

        # Update indentQuantity only if present and greater than 0
        if float(existing_data.get('indentQuantity', 0.0)) > 0.0:
            existing_data['indentQuantity'] = float(existing_data.get('indentQuantity', 0.0)) - float(issue_quantity)
        existing_data['indentQuantity'] = max(updated_indent, 0.0)

        # Update the current stock quantity
        current_qty = parse_float(existing_data.get('quantity', 0.0))
        new_qty = max(0.0, current_qty - parse_float(issue_quantity))
        existing_data['quantity'] = new_qty
        
                
        cur.execute("""
            UPDATE stock SET data =%s
            WHERE key = %s AND (data::json->>'invoice') = %s
        """, (json.dumps(existing_data),key, invoice))
        
        # Get row from indent_stock
        cur.execute("SELECT data FROM indent_stock WHERE key = %s", (key,))
        
        indentrow = cur.fetchone()
        if indentrow:
            indentrow = json.loads(indentrow[0])
        else:
            indentrow = None

        print("INDENT STOCK %s,%s",indentrow,issue_quantity,key);        
        
        if float(indentrow.get('indentQuantity', 0.0)) > 0.0:
            indentrow['indentQuantity'] = float(indentrow.get('indentQuantity', 0.0)) - float(issue_quantity)
        
                 
        cur.execute(
                    "UPDATE indent_stock SET data = %s WHERE key = %s",
                    (json.dumps(indentrow), key))
        
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Stock updated'}), 200

    except Exception as e:
        exc_type, exc_obj, tb = sys.exc_info()
        line_number = tb.tb_lineno
        print(f"Exception: {e} at line {line_number}")
        return jsonify({'error': str(e)}), 500

@app.route('/indent_stock', methods=['GET'])
def get_indent_stock():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT * FROM indent_stock')
    indent_stock = cur.fetchall()
    cur.close()
    conn.close()

    return jsonify(indent_stock)


@app.route('/stock', methods=['GET'])
def get_stock():
    is_job_specific = request.args.get('isJobSpecific', 'false').lower() == 'true'

    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT key, data FROM stock ORDER BY key')
    rows = cur.fetchall()
    cur.close()
    conn.close()

    stock_list = []
    for row in rows:
        data = json.loads(row[1])
        data['key'] = row[0]
        stock_list.append(data)

    filtered = [item for item in stock_list if ('serialNo' in item) == is_job_specific]
    return jsonify(filtered)

@app.route('/stock/save', methods=['POST'])
def save_stock():
    stock_data = request.json.get('stockData')
    is_job_specific = request.json.get('isJobSpecific', False)

    if not stock_data or not isinstance(stock_data, list):
        return jsonify({'error': 'stockData must be a list'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        for item in stock_data:
            m_type = item.get('type')
            subtype = item.get('subtype')
            serial_no = item.get('serialNo', None)

            if not m_type or not subtype:
                continue

            key = f"{m_type} - {subtype}"
            if is_job_specific and serial_no:
                key = f"{key} - {serial_no}"

            cur.execute(
                '''
                INSERT INTO stock (key, data) VALUES (%s, %s)
                ON CONFLICT (key) DO UPDATE SET data = EXCLUDED.data
                ''',
                (key, json.dumps(item))
            )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Stock saved'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ---------------- JOB INDENTS ----------------

@app.route('/job_indents', methods=['POST'])
def submit_job_indent():
    data = request.json.get('data')  # expecting list of indent dicts
   
    if not data or not isinstance(data, list):
        return jsonify({'error': 'List of indents expected'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()
        for indent in data:
            jobid = indent.get('serialNo')
            matType = indent.get('type')
            subType = indent.get('subtype')
            job_specific = indent.get('jobSpecific') is True 
            indentquantity = indent.get('quantity')
            if not jobid:
                continue
            
            if job_specific:
                stock_key = f"{matType} - {subType} - {jobid}"
            else:
                stock_key = f"{matType} - {subType}"
                
            # Fetch stock row
            cur.execute("SELECT data FROM indent_stock WHERE key = %s", (stock_key,))
            row = cur.fetchone()
            
            if row:
                stock_data = json.loads(row[0])
                existingindentQty = stock_data["indentQuantity"]
                stock_data["indentQuantity"] = existingindentQty + indentquantity
                # Save stock
                cur.execute(
                    "UPDATE indent_stock SET data = %s WHERE key = %s",
                    (json.dumps(stock_data), stock_key)
            )
            else:
                # Create new stock data
                stock_id = str(uuid.uuid4())
                stock_data = {
                    "indentQuantity": indentquantity
                }
                
                # Insert new stock row
                cur.execute(
                    "INSERT INTO indent_stock (key, data) VALUES (%s, %s)",
                    (stock_key, json.dumps(stock_data))
                )

                    
            cur.execute(
                'INSERT INTO job_indents (jobid, data) VALUES (%s, %s)',
                (jobid, json.dumps(indent))
            )
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({'message': 'Job indents submitted'}), 200
    except Exception as e:
        print("Exception: %s",str(e))
        return jsonify({'error': str(e)}), 500

@app.route('/job_indents/<jobid>', methods=['GET'])
def get_indents_for_job(jobid):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT data FROM job_indents WHERE jobid = %s', (jobid,))
    rows = cur.fetchall()
    cur.close()
    conn.close()

    indents = [json.loads(row[0]) for row in rows]
    return jsonify(indents)

@app.route('/job_indents', methods=['PUT'])
def update_job_indent():
    data = request.json
    if not data:
        return jsonify({'error': 'Missing indent data'}), 400

    jobid = data.get('serialNo')
    item_type = data.get('type')
    item_subtype = data.get('subtype')

    if not jobid:
        return jsonify({'error': 'serialNo is required'}), 401
    if not item_type or not item_subtype:
        return jsonify({'error': 'type and subtype are required'}), 402

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Check for matching row inside JSON
        cur.execute(
            '''
            SELECT * FROM job_indents
            WHERE jobid = %s
            AND data::json->>'type' = %s
            AND data::json->>'subtype' = %s
            ''',
            (jobid, item_type, item_subtype)
        )
        row = cur.fetchone()
        if not row:
            return jsonify({'error': 'Indent with matching jobid, type, and subtype not found'}), 400

        # Get the unique row ID
        indent_id = row[0]
        matched_indent = json.loads(row[2])
        matched_indent['price'] = data.get('price')
        matched_indent['issuedQty'] = data.get('issuedQty')
        matched_indent['issuedValue'] = data.get('issuedValue')
        matched_indent['jobSpecific'] = data.get('jobSpecific')
        matched_indent['user_out'] = data.get('user_out')
        matched_indent['out_time'] = data.get('out_time')

        # Update that row
        cur.execute(
            '''
            UPDATE job_indents
            SET data = %s
            WHERE id = %s
            ''',
            (json.dumps(matched_indent), indent_id)
        )

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({'message': 'Job indent updated'}), 200

    except Exception as e:
        print("Exception: %s",str(e))
        return jsonify({'error': str(e)}), 500



# -------------- HEALTH CHECK ----------------

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'OK'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
