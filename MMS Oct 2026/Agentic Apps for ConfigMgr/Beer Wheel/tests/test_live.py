"""Exercise the actual production WSGI import with two Gunicorn workers."""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request


def test_gunicorn_live_flow_and_restart(tmp_path):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    env = dict(os.environ, HOST_PIN='123456', BARTENDER_PIN='654321',
               SECRET_KEY='live-test-key-with-at-least-32-characters',
               DB_PATH=str(tmp_path / 'event.sqlite'), PUBLIC_BASE_URL=base)
    command = [sys.executable, '-m', 'gunicorn', '--bind', f'127.0.0.1:{port}',
               '--workers', '2', '--threads', '4', 'backend.app:app']

    def call(path, data=None, cookie=None, token=None):
        headers = {'Origin': base}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        if cookie:
            headers['Cookie'] = cookie
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(base + path, headers=headers,
                                     data=json.dumps(data).encode() if data is not None else None)
        try:
            response = urllib.request.urlopen(req, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        content = response.read()
        return response.status, json.loads(content) if response.headers.get_content_type() == 'application/json' else content, response.headers

    def start():
        server = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            if server.poll() is not None:
                raise AssertionError(server.stderr.read().decode())
            try:
                if call('/api/health')[0] == 200:
                    return server
            except (OSError, urllib.error.URLError):
                pass
            time.sleep(.05)
        server.terminate()
        server.wait(timeout=10)
        raise AssertionError('Gunicorn readiness timeout')

    def stop(server):
        server.terminate()
        server.wait(timeout=10)
        server.stderr.close()

    server = start()
    try:
        assert call('/api/health')[1] == {'status': 'ok'}
        status, attendee, _ = call('/api/sign-in', {'name': 'Squirrel'})
        assert status == 201
        token = attendee['token']
        status, _, headers = call('/api/host/auth', {'pin': '123456'})
        assert status == 200
        assert 'Secure' in headers['Set-Cookie']
        host = headers['Set-Cookie'].split(';')[0]
        assert call('/api/host/config', {'card_pool': 1}, host)[0] == 200
        assert call('/api/host/spin', {}, host)[0] == 200
        status, me, _ = call('/api/me', token=token)
        assert status == 200
        code = me['card']['code']
        status, state, _ = call('/api/state')
        assert state['remaining_cards'] == 0
        assert code not in json.dumps(state)
        _, _, headers = call('/api/redeem/auth', {'pin': '654321'})
        bartender = headers['Set-Cookie'].split(';')[0]
        assert call('/api/redeem/cards/' + code, {}, bartender)[0] == 200
        assert call('/api/redeem/cards/' + code, {}, bartender)[0] == 409
        assert call('/api/host/state', cookie=bartender)[0] == 401
    finally:
        stop(server)
    server = start()
    try:
        assert call('/api/me', token=token)[1]['card']['status'] == 'redeemed'
        assert call('/api/state')[1]['remaining_cards'] == 0
    finally:
        stop(server)
