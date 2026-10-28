# Beer Wheel — MMS October 2026

The live-build Event app from **Agentic Apps for ConfigMgr**. Attendees scan the Join QR code and Sign-in with a display name; the Host triggers a server-selected, unweighted Spin on the big-screen Wheel. A Winner receives a unique Beer card on the same phone; the Bartender can perform Redemption once. The Squirrel is decorative and has no effect on selection. This is a standalone Event demo, **not** an Intune or Configuration Manager integration.

**Live demo:** https://agentic-live.mauvtek.net/ (the deployed instance is managed separately from this repository).

- `/` — public Wheel and Join QR code.
- `/join` — Attendee Sign-in and private Beer card on the same phone/browser.
- `/host` — PIN-protected Host controls: Card pool, Sign-in, Spin, remove Attendees and Void active Beer cards.
- `/redeem` — separate PIN-protected Bartender Redemption.

## Run your own Event

Install Docker Compose. Copy `.env.example` to `.env` and set **different, random Host and Bartender PINs**, a random `SECRET_KEY` of at least 32 characters, and the exact HTTPS public origin in `PUBLIC_BASE_URL` (no trailing slash). `.env` is ignored by git. Never reuse live Event secrets or send them in a public chat. Set `BIND_ADDRESS` and `PORT` if you want to expose the container beyond the default loopback bind; use a reverse proxy with HTTPS and a valid certificate. The origin must match `PUBLIC_BASE_URL` or Host/Bartender POSTs will be rejected. Your reverse proxy must not access-log Beer card codes in Redemption URLs.

```sh
cp .env.example .env
# Edit .env locally; keep it private (chmod 600 .env)
docker compose up -d --build
curl -fsS http://127.0.0.1:8115/api/health
```

The default Card pool is 25; the Host can change it **before the first Spin**. Sign-in is open initially. SQLite state persists in the `event_data` Docker volume; never use `docker compose down -v` on an Event with real Attendees or Beer cards. If replacing the named volume with a bind mount, its directory must be writable by container UID 10001. The image serves the frontend and API on port 8000, with Gunicorn access logs disabled. The reverse proxy should disable request access logs for this hostname because Redemption paths contain private codes.

## Development and tests

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
PYTHONPATH=. .venv/bin/python -m pytest tests/ -q
cd frontend
npm install
npm test
```

The browser UI tests use Playwright/Chromium (`npx playwright install chromium` if missing). Backend tests cover authorization, one-time Redemption, no repeat Winner, Card pool limits, concurrency, Void, and durable data after a two-worker Gunicorn restart. The Wheel animation is presentation only; the server decides the Winner in a SQLite write transaction.

No attendee data, Beer card codes, live PINs, `.env`, or SQLite database are included here. Beer cards are Event-only vouchers, not a payment system. Venue rules and responsible service remain the Host's responsibility.
