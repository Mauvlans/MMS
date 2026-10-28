FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DB_PATH=/data/beer-wheel.sqlite
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home beerwheel && mkdir -p /data && chown beerwheel:beerwheel /data
COPY backend/*.py ./backend/
COPY frontend/index.html frontend/styles.css frontend/app.mjs frontend/core.mjs ./frontend/
USER beerwheel
EXPOSE 8000
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=3)"
# Access logging stays off: request paths and queries can contain Beer card codes.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "4", "--timeout", "30", "backend.app:app"]
