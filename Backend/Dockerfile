FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PETPAIR_HOST=0.0.0.0 PETPAIR_PORT=8765 PETPAIR_DB=/data/petpair.sqlite3
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt && groupadd --gid 10001 petpair && useradd --uid 10001 --gid 10001 --no-create-home petpair && mkdir /data && chown petpair:petpair /data
COPY server.py config.py migration.py manage.py probe.py ./
USER 10001:10001
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/health',timeout=2).read()"]
CMD ["python", "server.py"]
