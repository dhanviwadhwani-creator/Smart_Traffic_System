import sqlite3
import os
import base64
import uuid
from datetime import datetime

import requests
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

app = Flask(__name__)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # max 10 MB per request

DB_NAME = 'traffic.db'
CITY_CONTEXT = 'Kota, Rajasthan, India'
UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'uploads')
os.makedirs(UPLOAD_DIR, exist_ok=True)


def get_db():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn


def geocode(address):
    """Convert an address text into (lat, lng) using OpenStreetMap Nominatim.
    Returns (None, None) if it can't be found."""
    try:
        response = requests.get(
            'https://nominatim.openstreetmap.org/search',
            params={'q': f'{address}, {CITY_CONTEXT}', 'format': 'json', 'limit': 1},
            headers={'User-Agent': 'SmartTrafficAlertSystem/1.0 (student project)'},
            timeout=8,
        )
        results = response.json()
        if results:
            return float(results[0]['lat']), float(results[0]['lon'])
    except Exception as e:
        print('Geocoding failed:', e)
    return None, None


def init_db():
    conn = get_db()
    conn.execute(
        '''
        CREATE TABLE IF NOT EXISTS reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT NOT NULL,
            severity TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        '''
    )

    # Add lat/lng/photo columns to older databases that don't have them yet
    columns = [row['name'] for row in conn.execute('PRAGMA table_info(reports)')]
    if 'lat' not in columns:
        conn.execute('ALTER TABLE reports ADD COLUMN lat REAL')
    if 'lng' not in columns:
        conn.execute('ALTER TABLE reports ADD COLUMN lng REAL')
    if 'photo' not in columns:
        conn.execute('ALTER TABLE reports ADD COLUMN photo TEXT')
    conn.commit()

    # Fill coordinates for reports saved before geocoding existed
    rows = conn.execute('SELECT id, address FROM reports WHERE lat IS NULL').fetchall()
    for row in rows:
        lat, lng = geocode(row['address'])
        if lat is not None:
            conn.execute('UPDATE reports SET lat = ?, lng = ? WHERE id = ?', (lat, lng, row['id']))
    conn.commit()
    conn.close()


@app.route('/')
def home():
    return jsonify({'message': 'Smart Traffic Alert System backend is running!'})


@app.route('/api/reports', methods=['POST'])
def add_report():
    data = request.get_json(silent=True) or {}

    name = (data.get('name') or '').strip()
    phone = (data.get('phone') or '').strip()
    address = (data.get('address') or '').strip()
    severity = (data.get('severity') or '').strip()
    photo_b64 = data.get('photo') or ''

    if not name or not phone or not address:
        return jsonify({'error': 'name, phone and address are required'}), 400

    if severity not in ('Low', 'Moderate', 'Heavy'):
        return jsonify({'error': 'severity must be Low, Moderate or Heavy'}), 400

    # Save the photo (if any) as a file and keep only its name in the database
    photo_name = None
    if photo_b64:
        try:
            image_bytes = base64.b64decode(photo_b64)
            photo_name = uuid.uuid4().hex + '.jpg'
            with open(os.path.join(UPLOAD_DIR, photo_name), 'wb') as f:
                f.write(image_bytes)
        except Exception as e:
            print('Photo save failed:', e)
            photo_name = None

    lat, lng = geocode(address)

    conn = get_db()
    cursor = conn.execute(
        'INSERT INTO reports (name, phone, address, severity, created_at, lat, lng, photo) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        (name, phone, address, severity, datetime.now().isoformat(timespec='seconds'), lat, lng, photo_name),
    )
    conn.commit()
    report_id = cursor.lastrowid
    conn.close()

    return jsonify({'message': 'Report saved', 'id': report_id, 'lat': lat, 'lng': lng, 'photo': photo_name}), 201


@app.route('/api/reports', methods=['GET'])
def list_reports():
    conn = get_db()
    rows = conn.execute('SELECT * FROM reports ORDER BY id DESC').fetchall()
    conn.close()
    return jsonify([dict(row) for row in rows])


@app.route('/uploads/<path:filename>')
def get_upload(filename):
    return send_from_directory(UPLOAD_DIR, filename)


if __name__ == '__main__':
    init_db()
    app.run(debug=True, host='0.0.0.0', port=5000)