import os
import base64
import uuid
import time
from datetime import datetime

import requests
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from flask import Flask, jsonify, request, redirect
from flask_cors import CORS

load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL')
SUPABASE_URL = (os.getenv('SUPABASE_URL') or '').rstrip('/')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')
BUCKET = 'report-photos'

if not DATABASE_URL or not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    raise SystemExit(
        'Missing settings in .env. Need DATABASE_URL, SUPABASE_URL and SUPABASE_SERVICE_KEY.'
    )

app = Flask(__name__)
CORS(app)
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # max 10 MB per request

CITY_CONTEXT = 'Kota, Rajasthan, India'


def get_db():
    return psycopg2.connect(DATABASE_URL)


def photo_public_url(photo_name):
    return f'{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{photo_name}'


def upload_photo(image_bytes):
    """Upload image bytes to the Supabase bucket. Returns the file name, or None on failure."""
    photo_name = uuid.uuid4().hex + '.jpg'
    try:
        response = requests.post(
            f'{SUPABASE_URL}/storage/v1/object/{BUCKET}/{photo_name}',
            headers={
                'Authorization': f'Bearer {SUPABASE_SERVICE_KEY}',
                'apikey': SUPABASE_SERVICE_KEY,
                'Content-Type': 'image/jpeg',
            },
            data=image_bytes,
            timeout=30,
        )
        if response.status_code in (200, 201):
            return photo_name
        print('Photo upload failed:', response.status_code, response.text)
    except Exception as e:
        print('Photo upload failed:', e)
    return None


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
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(
        '''
        CREATE TABLE IF NOT EXISTS reports (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT NOT NULL,
            severity TEXT NOT NULL,
            created_at TEXT NOT NULL,
            lat DOUBLE PRECISION,
            lng DOUBLE PRECISION,
            photo TEXT
        )
        '''
    )
    conn.commit()

    # Fill coordinates for any reports that don't have them yet
    cur.execute('SELECT id, address FROM reports WHERE lat IS NULL')
    rows = cur.fetchall()
    for row in rows:
        lat, lng = geocode(row['address'])
        if lat is not None:
            cur.execute('UPDATE reports SET lat = %s, lng = %s WHERE id = %s', (lat, lng, row['id']))
        time.sleep(1)  # Nominatim allows about 1 request per second
    conn.commit()
    cur.close()
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

    # Upload the photo (if any) to Supabase Storage, keep only its name in the database
    photo_name = None
    if photo_b64:
        try:
            image_bytes = base64.b64decode(photo_b64)
            photo_name = upload_photo(image_bytes)
        except Exception as e:
            print('Photo decode failed:', e)
            photo_name = None

    lat, lng = geocode(address)

    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        'INSERT INTO reports (name, phone, address, severity, created_at, lat, lng, photo) '
        'VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id',
        (name, phone, address, severity, datetime.now().isoformat(timespec='seconds'), lat, lng, photo_name),
    )
    report_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({'message': 'Report saved', 'id': report_id, 'lat': lat, 'lng': lng, 'photo': photo_name}), 201


@app.route('/api/reports', methods=['GET'])
def list_reports():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute('SELECT * FROM reports ORDER BY id DESC')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([dict(row) for row in rows])


@app.route('/uploads/<path:filename>')
def get_upload(filename):
    # Photos now live in Supabase Storage; send the app there so old URLs keep working
    return redirect(photo_public_url(filename))


if __name__ == '__main__':
    init_db()
    app.run(debug=True, host='0.0.0.0', port=5000)
