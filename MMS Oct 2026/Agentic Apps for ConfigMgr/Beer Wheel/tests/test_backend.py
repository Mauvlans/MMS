import importlib
from pathlib import Path

import pytest


@pytest.fixture
def app(tmp_path, monkeypatch):
    monkeypatch.setenv('HOST_PIN', '123456')
    monkeypatch.setenv('BARTENDER_PIN', '654321')
    monkeypatch.setenv('SECRET_KEY', 'test-secret-key-with-at-least-32-characters')
    monkeypatch.setenv('DB_PATH', str(tmp_path / 'bootstrap.sqlite'))
    assert Path('backend/app.py').exists(), 'Backend app must exist'
    module = importlib.import_module('backend.app')
    return module.create_app({
        'TESTING': True,
        'DB_PATH': str(tmp_path / 'event.sqlite'),
        'PUBLIC_BASE_URL': 'https://event.example',
        'COOKIE_SECURE': False,
    })


@pytest.fixture
def client(app):
    return app.test_client()


def test_health_checks_durable_database(client, app):
    assert client.get('/api/health').status_code == 200
    assert client.get('/api/health').json == {'status': 'ok'}
    assert Path(app.config['DB_PATH']).is_file()


ORIGIN = {'Origin': 'https://event.example'}


def host_login(client):
    return client.post('/api/host/auth', json={'pin': '123456'}, headers=ORIGIN)


def bartender_login(client):
    return client.post('/api/redeem/auth', json={'pin': '654321'}, headers=ORIGIN)


def test_role_authentication_isolated_and_cookie_flags(app, client):
    assert client.get('/api/host/state').status_code == 401
    assert client.post('/api/host/auth', json={'pin': 'wrong'}, headers=ORIGIN).status_code == 401
    assert client.post('/api/host/auth', json={'pin': '654321'}, headers=ORIGIN).status_code == 401
    response = host_login(client)
    assert response.status_code == 200
    assert 'HttpOnly' in response.headers['Set-Cookie']
    assert 'SameSite=Strict' in response.headers['Set-Cookie']
    assert client.get('/api/host/state').json['cards'] == []
    assert client.get('/api/redeem/cards?code=anything').status_code == 401
    bartender = app.test_client()
    assert bartender_login(bartender).status_code == 200
    assert bartender.get('/api/host/state').status_code == 401
    assert bartender.get('/api/redeem/cards?code=anything').status_code == 404


def test_cookie_auth_requires_same_origin(client):
    assert client.post('/api/host/auth', json={'pin': '123456'}).status_code == 403
    assert client.post('/api/host/auth', json={'pin': '123456'}, headers={'Origin': 'https://evil.example'}).status_code == 403
    assert host_login(client).status_code == 200


def sign_in(client, name='Squirrel', email=None):
    data = {'name': name}
    if email is not None:
        data['email'] = email
    return client.post('/api/sign-in', json=data)


def test_attendee_sign_in_token_and_public_privacy(client, app):
    result = sign_in(client, 'Ada', 'ada@example.com')
    assert result.status_code == 201
    token = result.json['token']
    assert len(token) >= 32
    attendee = result.json['attendee']
    state = client.get('/api/state').json
    assert state['attendee_count'] == 1
    assert state['eligible'] == [attendee]
    assert state['card_pool'] == state['remaining_cards'] == 25
    assert state['latest_spin'] is None
    assert 'ada@example.com' not in str(state) and token not in str(state)
    assert client.get('/api/me').status_code == 401
    assert client.get('/api/me', headers={'Authorization': 'Bearer wrong'}).status_code == 401
    me = client.get('/api/me', headers={'Authorization': 'Bearer ' + token})
    assert me.json == {'attendee': attendee, 'card': None}
    import sqlite3
    with sqlite3.connect(app.config['DB_PATH']) as db:
        stored = db.execute('SELECT token_hash FROM attendees').fetchone()[0]
        assert stored != token
        assert token.encode() not in Path(app.config['DB_PATH']).read_bytes()
    host_login(client)
    assert client.get('/api/host/state').json['attendees'][0]['email'] == 'ada@example.com'


def test_host_can_close_sign_in_and_reopen(client):
    host_login(client)
    closed = client.post('/api/host/sign-in', json={'open': False}, headers=ORIGIN)
    assert closed.status_code == 200
    assert closed.json['sign_in_open'] is False
    assert closed.json['event']['status'] == 'closed'
    assert sign_in(client).status_code == 409
    assert client.get('/api/state').json['attendee_count'] == 0
    assert client.post('/api/host/sign-in', json={'open': True}, headers=ORIGIN).status_code == 200
    assert sign_in(client).status_code == 201


def test_configure_card_pool_before_spins(client):
    host_login(client)
    response = client.post('/api/host/config', json={'card_pool': 2}, headers=ORIGIN)
    assert response.status_code == 200
    assert response.json['card_pool'] == response.json['remaining_cards'] == 2
    for bad in [True, -1, 10001, '2', 2.5, None]:
        assert client.post('/api/host/config', json={'card_pool': bad}, headers=ORIGIN).status_code == 400
    assert client.get('/api/state').json['card_pool'] == 2


def test_remove_attendee_preserves_history_revokes_token(client):
    attendee = sign_in(client).json
    host_login(client)
    removed = client.post('/api/host/attendees/' + str(attendee['attendee']['id']) + '/remove', headers=ORIGIN)
    assert removed.status_code == 200
    state = client.get('/api/state').json
    assert state['eligible'] == [] and state['attendee_count'] == 0
    assert client.get('/api/me', headers={'Authorization': 'Bearer ' + attendee['token']}).status_code == 401
    assert client.get('/api/host/state').json['attendees'][0]['removed'] == 1
    assert client.post('/api/host/attendees/9999/remove', headers=ORIGIN).status_code == 404


def test_spin_issues_private_beer_card_and_locks_configuration(client):
    attendee = sign_in(client, 'Ada', 'ada@example.com').json
    host_login(client)
    response = client.post('/api/host/spin', headers=ORIGIN)
    assert response.status_code == 200
    spin = response.json['spin']
    assert spin['id'] > 0
    assert spin['winner'] == attendee['attendee']
    assert spin['winner_id'] == attendee['attendee']['id']
    assert spin['winner_name'] == 'Ada'
    state = client.get('/api/state').json
    assert state['latest_spin'] == spin
    assert state['eligible'] == []
    assert state['remaining_cards'] == 24
    me = client.get('/api/me', headers={'Authorization': 'Bearer ' + attendee['token']}).json
    assert me['card']['id'] == spin['card_id']
    assert me['card']['status'] == 'active'
    assert len(me['card']['code']) >= 12
    assert me['card']['code'] not in str(state)
    assert 'ada@example.com' not in str(state)
    assert client.get('/api/host/state').json['cards'] == [me['card']]
    assert client.post('/api/host/config', json={'card_pool': 2}, headers=ORIGIN).status_code == 409


def test_pool_exhausted_blocks_spins(client):
    host_login(client)
    client.post('/api/host/config', json={'card_pool': 1}, headers=ORIGIN)
    sign_in(client, 'Ada')
    sign_in(client, 'Grace')
    assert client.post('/api/host/spin', headers=ORIGIN).status_code == 200
    blocked = client.post('/api/host/spin', headers=ORIGIN)
    assert blocked.status_code == 409
    assert blocked.json['code'] == 'pool_exhausted'
    state = client.get('/api/state').json
    assert state['remaining_cards'] == 0
    assert len(state['eligible']) == 1
    assert len(client.get('/api/host/state').json['cards']) == 1


def test_attendee_cannot_win_twice(client):
    sign_in(client)
    host_login(client)
    assert client.post('/api/host/spin', headers=ORIGIN).status_code == 200
    again = client.post('/api/host/spin', headers=ORIGIN)
    assert again.status_code == 409
    assert again.json['code'] == 'no_eligible'
    assert len(client.get('/api/host/state').json['cards']) == 1


def issue_card(client):
    attendee = sign_in(client).json
    host_login(client)
    assert client.post('/api/host/spin', headers=ORIGIN).status_code == 200
    return client.get('/api/me', headers={'Authorization': 'Bearer ' + attendee['token']}).json['card']


def test_redemption_is_one_time_and_does_not_restore_capacity(app, client):
    card = issue_card(client)
    bartender = app.test_client()
    bartender_login(bartender)
    assert bartender.get('/api/redeem/cards?code=' + card['code']).json['card'] == card
    assert bartender.get('/api/redeem/cards').status_code == 400
    response = bartender.post('/api/redeem/cards/' + card['code'], headers=ORIGIN)
    assert response.status_code == 200
    assert response.json['card']['status'] == 'redeemed'
    assert response.json['card']['redeemed_at'] is not None
    repeated = bartender.post('/api/redeem/cards/' + card['code'], headers=ORIGIN)
    assert repeated.status_code == 409
    assert client.get('/api/state').json['remaining_cards'] == 24


def test_void_restores_capacity_but_prior_winner_stays_ineligible(app, client):
    host_login(client)
    client.post('/api/host/config', json={'card_pool': 1}, headers=ORIGIN)
    card = issue_card(client)
    assert client.get('/api/state').json['remaining_cards'] == 0
    path = '/api/host/cards/' + str(card['id']) + '/void'
    assert client.post(path, headers=ORIGIN).status_code == 200
    assert client.get('/api/state').json['remaining_cards'] == 1
    assert client.get('/api/state').json['eligible'] == []
    assert client.post('/api/host/spin', headers=ORIGIN).json['code'] == 'no_eligible'
    assert client.post(path, headers=ORIGIN).status_code == 409
    bartender_login(client)
    assert client.post('/api/redeem/cards/' + card['code'], headers=ORIGIN).status_code == 409
    sign_in(client, 'Next Attendee')
    assert client.post('/api/host/spin', headers=ORIGIN).status_code == 200
    assert client.get('/api/state').json['remaining_cards'] == 0
    assert len(client.get('/api/host/state').json['cards']) == 2


def test_pin_rate_limit_is_durable_and_role_scoped(app, client):
    app.config['PIN_RATE_LIMIT'] = 2
    for _ in range(2):
        assert client.post('/api/host/auth', json={'pin': 'wrong'}, headers=ORIGIN).status_code == 401
    limited = host_login(client)
    assert limited.status_code == 429
    assert int(limited.headers['Retry-After']) > 0
    assert bartender_login(client).status_code == 200
    module = importlib.import_module('backend.app')
    reopened = module.create_app(dict(app.config)).test_client()
    assert host_login(reopened).status_code == 429


def test_sign_in_rate_limit_handles_shared_event_network(app, client):
    assert app.config['SIGN_IN_RATE_LIMIT'] >= 300
    app.config['SIGN_IN_RATE_LIMIT'] = 2
    assert sign_in(client, 'Ada').status_code == 201
    assert sign_in(client, 'Grace').status_code == 201
    assert sign_in(client, 'Third').status_code == 429
    assert client.get('/api/state').json['attendee_count'] == 2


def test_concurrent_spins_never_over_issue_or_repeat_winners(app, client):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    host_login(client)
    client.post('/api/host/config', json={'card_pool': 7}, headers=ORIGIN)
    for i in range(12):
        assert sign_in(client, f'Attendee {i}').status_code == 201
    cookie = client.get_cookie('beer_host', path='/api/host').value
    gate = Barrier(12)
    def run(_):
        worker = app.test_client()
        worker.set_cookie('beer_host', cookie, path='/api/host')
        gate.wait(timeout=10)
        response = worker.post('/api/host/spin', headers=ORIGIN)
        return response.status_code, response.json
    with ThreadPoolExecutor(max_workers=12) as executor:
        results = list(executor.map(run, range(12)))
    assert sorted(status for status, _ in results) == [200] * 7 + [409] * 5
    winners = [data['spin']['winner_id'] for status, data in results if status == 200]
    assert len(set(winners)) == 7
    state = client.get('/api/host/state').json
    assert state['remaining_cards'] == 0
    assert len(state['cards']) == 7
    assert len({card['code'] for card in state['cards']}) == 7
    assert len(state['eligible']) == 5


def test_concurrent_redemption_has_exactly_one_success(app, client):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    card = issue_card(client)
    bartender_login(client)
    cookie = client.get_cookie('beer_bartender', path='/api/redeem').value
    gate = Barrier(2)
    def run(_):
        worker = app.test_client()
        worker.set_cookie('beer_bartender', cookie, path='/api/redeem')
        gate.wait(timeout=10)
        return worker.post('/api/redeem/cards/' + card['code'], headers=ORIGIN).status_code
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(run, range(2)))
    assert sorted(results) == [200, 409]
    assert client.post('/api/host/cards/' + str(card['id']) + '/void', headers=ORIGIN).status_code == 409


@pytest.mark.parametrize('path,payload', [
    ('/api/host/config', {'card_pool': 3}),
    ('/api/host/sign-in', {'open': False}),
    ('/api/host/spin', {}),
    ('/api/host/attendees/1/remove', {}),
    ('/api/host/cards/1/void', {}),
    ('/api/redeem/cards/anything', {}),
])
def test_all_cookie_mutations_reject_wrong_role_and_origin(app, client, path, payload):
    assert client.post(path, json=payload, headers=ORIGIN).status_code == 401
    if path.startswith('/api/host'):
        bartender_login(client)
    else:
        host_login(client)
    assert client.post(path, json=payload, headers=ORIGIN).status_code == 401
    host_login(client)
    bartender_login(client)
    assert client.post(path, json=payload).status_code == 403
    assert client.post(path, json=payload, headers={'Origin': 'https://evil.example'}).status_code == 403


def test_qr_and_spa_routes_are_served_without_api_fallback(app, client, tmp_path):
    frontend = tmp_path / 'frontend'
    frontend.mkdir()
    (frontend / 'index.html').write_text('<html><title>Beer Wheel</title></html>')
    (frontend / 'app.js').write_text('/* Squirrel */')
    app.config['FRONTEND_DIR'] = str(frontend)
    qr = client.get('/api/qr')
    assert qr.status_code == 200
    assert qr.mimetype == 'image/png'
    assert qr.data.startswith(b'\x89PNG\r\n\x1a\n')
    for path in ['/', '/join', '/host', '/redeem']:
        response = client.get(path)
        assert response.status_code == 200
        assert b'Beer Wheel' in response.data
    assert client.get('/app.js').data == b'/* Squirrel */'
    assert client.get('/api/missing').status_code == 404
    assert client.get('/api/missing').is_json
    assert client.get('/../../backend/app.py').status_code == 404


def test_api_responses_are_not_cached_or_embeddable(client):
    response = client.get('/api/state')
    assert response.headers['Cache-Control'] == 'no-store'
    assert response.headers['X-Content-Type-Options'] == 'nosniff'
    assert response.headers['Referrer-Policy'] == 'no-referrer'
    assert response.headers['X-Frame-Options'] == 'DENY'


def test_health_checks_all_required_storage_tables(app, client):
    import sqlite3
    with sqlite3.connect(app.config['DB_PATH']) as db:
        db.execute('DROP TABLE cards')
    response = client.get('/api/health')
    assert response.status_code == 503
    assert response.json == {'status': 'unavailable'}


def test_storage_failures_do_not_log_beer_card_codes(app, client, caplog):
    import sqlite3
    bartender_login(client)
    with sqlite3.connect(app.config['DB_PATH']) as db:
        db.execute('DROP TABLE cards')
    response = client.get('/api/redeem/cards?code=PRIVATE-CODE-MUST-NOT-BE-LOGGED')
    assert response.status_code == 503
    assert response.json['code'] == 'storage_unavailable'
    assert 'PRIVATE-CODE' not in caplog.text
    assert app.config['DB_PATH'] not in str(response.json)


def test_future_database_version_is_rejected_without_rewriting(app):
    import sqlite3
    with sqlite3.connect(app.config['DB_PATH']) as db:
        db.execute('PRAGMA user_version=99')
    module = importlib.import_module('backend.app')
    with pytest.raises(RuntimeError, match='schema'):
        module.create_app(dict(app.config))
    with sqlite3.connect(app.config['DB_PATH']) as db:
        assert db.execute('PRAGMA user_version').fetchone()[0] == 99


@pytest.mark.parametrize('overrides', [
    {'SECRET_KEY': ''}, {'SECRET_KEY': 'short'},
    {'HOST_PIN': ''}, {'BARTENDER_PIN': ''},
    {'HOST_PIN': 'samepin', 'BARTENDER_PIN': 'samepin'},
])
def test_startup_rejects_unsafe_credentials(app, overrides):
    config = dict(app.config)
    config.update(overrides)
    with pytest.raises(RuntimeError):
        importlib.import_module('backend.app').create_app(config)
