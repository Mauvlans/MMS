"""Single Event Beer Wheel. All persisted commands use SQLite write locks."""
import os
import hashlib
import hmac
import sqlite3
import secrets
import re
import time
from io import BytesIO
from contextlib import contextmanager
from pathlib import Path

from flask import Flask, jsonify, request, send_file, send_from_directory
import qrcode
from itsdangerous import URLSafeTimedSerializer, BadSignature
from werkzeug.exceptions import HTTPException


class PolicyError(Exception):
    def __init__(self, message, code='invalid', status=400):
        self.message, self.code, self.status = message, code, status


def body():
    if request.mimetype != 'application/json':
        raise PolicyError('JSON required', 'invalid_json')
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise PolicyError('JSON object required', 'invalid_json')
    return data


def fingerprint(value):
    return hashlib.sha256(value.encode()).hexdigest()


def connect(app):
    db = sqlite3.connect(app.config['DB_PATH'], timeout=15, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('PRAGMA busy_timeout=15000')
    return db


@contextmanager
def transaction(app, write=False):
    db = connect(app)
    try:
        db.execute('BEGIN IMMEDIATE' if write else 'BEGIN')
        yield db
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def create_app(config=None):
    app = Flask(__name__, static_folder=None)
    app.config.from_mapping(
        DB_PATH=os.environ.get('DB_PATH', '/data/beer-wheel.sqlite'),
        HOST_PIN=os.environ.get('HOST_PIN'),
        BARTENDER_PIN=os.environ.get('BARTENDER_PIN'),
        SECRET_KEY=os.environ.get('SECRET_KEY'),
        PUBLIC_BASE_URL=os.environ.get('PUBLIC_BASE_URL', 'http://localhost:8000').rstrip('/'),
        COOKIE_SECURE=True,
        MAX_CONTENT_LENGTH=8192,
        PIN_RATE_LIMIT=10,
        SIGN_IN_RATE_LIMIT=600,
        FRONTEND_DIR=str(Path(__file__).resolve().parent.parent / 'frontend'),
    )
    app.config.update(config or {})
    if not all(isinstance(app.config.get(k), str) and app.config[k] for k in ('HOST_PIN', 'BARTENDER_PIN', 'SECRET_KEY')):
        raise RuntimeError('HOST_PIN, BARTENDER_PIN, and SECRET_KEY are required')
    if len(app.config['SECRET_KEY']) < 32:
        raise RuntimeError('SECRET_KEY must be at least 32 characters')
    if hmac.compare_digest(app.config['HOST_PIN'].encode(), app.config['BARTENDER_PIN'].encode()):
        raise RuntimeError('HOST_PIN and BARTENDER_PIN must differ')
    Path(app.config['DB_PATH']).parent.mkdir(parents=True, exist_ok=True)
    with transaction(app, write=True) as db:
        if db.execute('PRAGMA user_version').fetchone()[0] not in (0, 1):
            raise RuntimeError('Unsupported database schema version')
        db.execute('CREATE TABLE IF NOT EXISTS event (id INTEGER PRIMARY KEY CHECK(id=1), sign_in_open INTEGER NOT NULL DEFAULT 1 CHECK(sign_in_open IN (0,1)), card_pool INTEGER NOT NULL DEFAULT 25 CHECK(card_pool>=0))')
        db.execute('INSERT OR IGNORE INTO event(id) VALUES(1)')
        db.execute('''CREATE TABLE IF NOT EXISTS attendees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
            email TEXT,
            token_hash TEXT NOT NULL UNIQUE,
            removed INTEGER NOT NULL DEFAULT 0 CHECK(removed IN (0,1)),
            has_won INTEGER NOT NULL DEFAULT 0 CHECK(has_won IN (0,1)),
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        )''')
        db.execute('''CREATE TABLE IF NOT EXISTS cards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            attendee_id INTEGER NOT NULL UNIQUE REFERENCES attendees(id),
            code TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','redeemed','void')),
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
            redeemed_at TEXT,
            voided_at TEXT
        )''')
        db.execute('''CREATE TABLE IF NOT EXISTS spins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            attendee_id INTEGER NOT NULL UNIQUE REFERENCES attendees(id),
            winner_name TEXT NOT NULL,
            card_id INTEGER NOT NULL UNIQUE REFERENCES cards(id)
        )''')
        db.execute('''CREATE TABLE IF NOT EXISTS rate_limits (
            bucket TEXT PRIMARY KEY,
            attempts INTEGER NOT NULL CHECK(attempts>=0),
            expires_at INTEGER NOT NULL
        )''')
        db.execute('PRAGMA user_version=1')

    roles = {'host': ('HOST_PIN', 'beer_host'), 'redeem': ('BARTENDER_PIN', 'beer_bartender')}

    def serializer(role):
        pin_key, _ = roles[role]
        return URLSafeTimedSerializer(app.config['SECRET_KEY'], salt=role + fingerprint(app.config[pin_key]))

    @app.errorhandler(PolicyError)
    def policy_error(error):
        response = jsonify(error=error.message, code=error.code)
        if error.status == 429:
            response.headers['Retry-After'] = str(getattr(error, 'retry_after', 600))
        return response, error.status

    @app.errorhandler(sqlite3.Error)
    def storage_error(error):
        # Never log the request URL: Redemption paths/queries carry Beer card codes.
        return jsonify(error='Event storage unavailable', code='storage_unavailable'), 503

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(error=error.name, code='http_error'), error.code

    @app.after_request
    def response_headers(response):
        if request.path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        return response

    @app.before_request
    def protect_roles():
        for role, (_, cookie) in roles.items():
            if not request.path.startswith('/api/' + role + '/'):
                continue
            if request.method not in ('GET', 'HEAD', 'OPTIONS'):
                if request.headers.get('Origin') != app.config['PUBLIC_BASE_URL']:
                    raise PolicyError('Same-origin request required', 'origin', 403)
            if request.path == '/api/' + role + '/auth':
                return None
            try:
                value = serializer(role).loads(request.cookies.get(cookie, ''), max_age=43200)
                if value != role:
                    raise BadSignature('Role mismatch')
            except BadSignature:
                raise PolicyError('Authentication required', 'unauthorized', 401)
        return None

    def rate_limit(scope, limit, seconds):
        now = int(time.time())
        bucket = fingerprint(scope + ':' + (request.remote_addr or 'unknown'))
        with transaction(app, write=True) as db:
            db.execute('DELETE FROM rate_limits WHERE expires_at<=?', (now,))
            record = db.execute('SELECT attempts,expires_at FROM rate_limits WHERE bucket=?', (bucket,)).fetchone()
            if record and record['attempts'] >= limit:
                error = PolicyError('Please wait before trying again', 'rate_limited', 429)
                error.retry_after = max(1, record['expires_at'] - now)
                raise error
            db.execute('''INSERT INTO rate_limits(bucket,attempts,expires_at) VALUES(?,1,?)
                          ON CONFLICT(bucket) DO UPDATE SET attempts=attempts+1''', (bucket, now + seconds))

    def authenticate(role):
        rate_limit('pin:' + role, app.config['PIN_RATE_LIMIT'], 600)
        pin = body().get('pin')
        key, cookie = roles[role]
        if not isinstance(pin, str) or not hmac.compare_digest(pin.encode(), app.config[key].encode()):
            raise PolicyError('PIN not accepted', 'unauthorized', 401)
        response = jsonify(ok=True)
        response.set_cookie(cookie, serializer(role).dumps(role), max_age=43200,
                            httponly=True, secure=app.config['COOKIE_SECURE'], samesite='Strict', path='/api/' + role)
        return response

    @app.post('/api/host/auth')
    def host_auth():
        return authenticate('host')

    @app.post('/api/redeem/auth')
    def bartender_auth():
        return authenticate('redeem')

    card_query = '''SELECT c.id,c.code,c.status,c.attendee_id,a.name AS attendee_name,
                    c.created_at,c.redeemed_at,c.voided_at FROM cards c JOIN attendees a ON a.id=c.attendee_id'''

    def spin_view(row):
        if row is None:
            return None
        return dict(id=row['id'], winner=dict(id=row['attendee_id'], name=row['winner_name']),
                    winner_id=row['attendee_id'], winner_name=row['winner_name'], card_id=row['card_id'])

    def state(db, private=False):
        event = db.execute('SELECT * FROM event WHERE id=1').fetchone()
        opened = bool(event['sign_in_open'])
        result = dict(
            event=dict(name='Event', status='open' if opened else 'closed', sign_in_open=opened),
            sign_in_open=opened,
            attendee_count=db.execute('SELECT COUNT(*) FROM attendees WHERE removed=0').fetchone()[0],
            eligible=[dict(row) for row in db.execute('SELECT id,name FROM attendees WHERE removed=0 AND has_won=0 ORDER BY id')],
            remaining_cards=event['card_pool'] - db.execute("SELECT COUNT(*) FROM cards WHERE status!='void'").fetchone()[0],
            card_pool=event['card_pool'], latest_spin=spin_view(db.execute('SELECT * FROM spins ORDER BY id DESC LIMIT 1').fetchone()),
        )
        if private:
            result['attendees'] = [dict(row) for row in db.execute('SELECT id,name,email,removed,has_won,created_at FROM attendees ORDER BY id')]
            result['cards'] = [dict(row) for row in db.execute(card_query + ' ORDER BY c.id DESC')]
        return result

    @app.get('/api/state')
    def public_state():
        with transaction(app) as db:
            return jsonify(state(db))

    @app.post('/api/sign-in')
    def sign_in():
        rate_limit('sign-in', app.config['SIGN_IN_RATE_LIMIT'], 3600)
        data = body()
        name, email = data.get('name'), data.get('email')
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80 or any(ord(c) < 32 for c in name):
            raise PolicyError('Attendee name required, at most 80 characters', 'invalid_name')
        if email is not None:
            if not isinstance(email, str) or len(email) > 254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
                raise PolicyError('Email not accepted', 'invalid_email')
        token = secrets.token_urlsafe(32)
        with transaction(app, write=True) as db:
            if not db.execute('SELECT sign_in_open FROM event WHERE id=1').fetchone()[0]:
                raise PolicyError('Sign-in is closed', 'sign_in_closed', 409)
            row_id = db.execute('INSERT INTO attendees(name,email,token_hash) VALUES(?,?,?)', (name.strip(), email, fingerprint(token))).lastrowid
        return jsonify(token=token, attendee=dict(id=row_id, name=name.strip())), 201

    @app.get('/api/me')
    def me():
        authorization = request.headers.get('Authorization', '')
        if not authorization.startswith('Bearer ') or len(authorization) > 256:
            raise PolicyError('Attendee authentication required', 'unauthorized', 401)
        with transaction(app) as db:
            attendee = db.execute('SELECT id,name FROM attendees WHERE token_hash=? AND removed=0', (fingerprint(authorization[7:]),)).fetchone()
            if attendee is None:
                raise PolicyError('Attendee authentication required', 'unauthorized', 401)
            card = db.execute(card_query + ' WHERE c.attendee_id=?', (attendee['id'],)).fetchone()
            return jsonify(attendee=dict(attendee), card=dict(card) if card else None)

    @app.get('/api/host/state')
    def host_state():
        with transaction(app) as db:
            return jsonify(state(db, private=True))

    @app.post('/api/host/sign-in')
    def set_sign_in():
        opened = body().get('open')
        if type(opened) is not bool:
            raise PolicyError('Sign-in open must be boolean', 'invalid_open')
        with transaction(app, write=True) as db:
            db.execute('UPDATE event SET sign_in_open=? WHERE id=1', (int(opened),))
            return jsonify(state(db))

    @app.post('/api/host/config')
    def configure():
        pool = body().get('card_pool')
        if type(pool) is not int or not 0 <= pool <= 10000:
            raise PolicyError('Card pool must be an integer from 0 to 10000', 'invalid_pool')
        with transaction(app, write=True) as db:
            if db.execute('SELECT 1 FROM spins LIMIT 1').fetchone():
                raise PolicyError('Card pool cannot change after a Spin', 'pool_locked', 409)
            db.execute('UPDATE event SET card_pool=? WHERE id=1', (pool,))
            return jsonify(state(db))

    @app.post('/api/host/attendees/<int:attendee_id>/remove')
    def remove_attendee(attendee_id):
        with transaction(app, write=True) as db:
            if db.execute('UPDATE attendees SET removed=1 WHERE id=?', (attendee_id,)).rowcount != 1:
                raise PolicyError('Attendee not found', 'not_found', 404)
        return jsonify(ok=True)

    @app.post('/api/host/spin')
    def spin():
        with transaction(app, write=True) as db:
            pool = db.execute('SELECT card_pool FROM event WHERE id=1').fetchone()[0]
            issued = db.execute("SELECT COUNT(*) FROM cards WHERE status!='void'").fetchone()[0]
            if issued >= pool:
                raise PolicyError('Card pool exhausted', 'pool_exhausted', 409)
            eligible = db.execute('SELECT id,name FROM attendees WHERE removed=0 AND has_won=0 ORDER BY id').fetchall()
            if not eligible:
                raise PolicyError('No eligible Attendee', 'no_eligible', 409)
            winner = secrets.choice(eligible)
            card_id = db.execute('INSERT INTO cards(attendee_id,code) VALUES(?,?)', (winner['id'], secrets.token_hex(8).upper())).lastrowid
            db.execute('UPDATE attendees SET has_won=1 WHERE id=?', (winner['id'],))
            db.execute('INSERT INTO spins(attendee_id,winner_name,card_id) VALUES(?,?,?)', (winner['id'], winner['name'], card_id))
            result = state(db)
            result['spin'] = result['latest_spin']
            return jsonify(result)

    @app.post('/api/host/cards/<int:card_id>/void')
    def void_card(card_id):
        with transaction(app, write=True) as db:
            card = db.execute('SELECT status FROM cards WHERE id=?', (card_id,)).fetchone()
            if card is None:
                raise PolicyError('Beer card not found', 'not_found', 404)
            if card['status'] != 'active':
                raise PolicyError('Only an active Beer card can be Void', 'card_inactive', 409)
            db.execute("UPDATE cards SET status='void',voided_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=? AND status='active'", (card_id,))
        return jsonify(ok=True)

    def card_by_code(db, code):
        if not isinstance(code, str) or not code or len(code) > 64:
            raise PolicyError('Beer card code required', 'invalid_code')
        card = db.execute(card_query + ' WHERE c.code=?', (code,)).fetchone()
        if card is None:
            raise PolicyError('Beer card not found', 'not_found', 404)
        return dict(card)

    @app.get('/api/redeem/cards')
    def find_card():
        with transaction(app) as db:
            return jsonify(card=card_by_code(db, request.args.get('code')))

    @app.post('/api/redeem/cards/<code>')
    def redeem_card(code):
        with transaction(app, write=True) as db:
            card = card_by_code(db, code)
            if card['status'] != 'active':
                raise PolicyError('Beer card is not active', 'card_inactive', 409)
            db.execute("UPDATE cards SET status='redeemed',redeemed_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=? AND status='active'", (card['id'],))
            return jsonify(card=card_by_code(db, code))

    @app.get('/api/health')
    def health():
        try:
            with transaction(app) as db:
                if db.execute('SELECT card_pool FROM event WHERE id=1').fetchone() is None:
                    raise sqlite3.DatabaseError('Event unavailable')
                db.execute('SELECT id,name,token_hash,removed,has_won FROM attendees LIMIT 1').fetchone()
                db.execute('SELECT id,code,status,attendee_id FROM cards LIMIT 1').fetchone()
                db.execute('SELECT id,attendee_id,winner_name,card_id FROM spins LIMIT 1').fetchone()
                db.execute('SELECT bucket,attempts,expires_at FROM rate_limits LIMIT 1').fetchone()
                if db.execute('PRAGMA user_version').fetchone()[0] != 1:
                    raise sqlite3.DatabaseError('Schema unavailable')
            return jsonify(status='ok')
        except sqlite3.Error:
            return jsonify(status='unavailable'), 503

    @app.get('/api/qr')
    def join_qr():
        output = BytesIO()
        qrcode.make(app.config['PUBLIC_BASE_URL'] + '/join').save(output, format='PNG')
        output.seek(0)
        return send_file(output, mimetype='image/png', max_age=0)

    @app.get('/')
    @app.get('/join')
    @app.get('/host')
    @app.get('/redeem')
    def frontend():
        return send_from_directory(app.config['FRONTEND_DIR'], 'index.html')

    @app.get('/<path:asset>')
    def frontend_asset(asset):
        if asset == 'api' or asset.startswith('api/'):
            raise PolicyError('Not found', 'not_found', 404)
        return send_from_directory(app.config['FRONTEND_DIR'], asset)

    return app


app = create_app()
