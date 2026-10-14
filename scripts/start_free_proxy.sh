#!/usr/bin/env bash
# Fedora/Linux: interactive token stays out of shell history and command arguments.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v python3 >/dev/null || { echo "Нужен Python 3.10+." >&2; exit 1; }
command -v cloudflared >/dev/null || { echo "Установите cloudflared по инструкции." >&2; exit 1; }
read -r -s -p "API-токен alerts.in.ua (скрыто): " TOKEN; echo
[[ -n "$TOKEN" ]] || { echo "Токен пуст." >&2; exit 1; }
ALERTS_TOKEN="$TOKEN" BIND_HOST=127.0.0.1 PORT=8080 python3 server/app.py &
PROXY_PID=$!
unset TOKEN
trap 'kill "$PROXY_PID" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sleep 1
kill -0 "$PROXY_PID" 2>/dev/null || { echo "Сервер завершился: проверьте Python/порт 8080." >&2; exit 1; }
python3 - <<'PY'
import json,urllib.request
with urllib.request.urlopen("http://127.0.0.1:8080/health",timeout=3) as response:
    assert json.load(response)["service"] == "svitanok"
PY
echo "Скопируйте HTTPS-адрес trycloudflare.com в приложение."
echo "Это временный тестовый туннель. Компьютер должен оставаться включённым."
cloudflared tunnel --url http://127.0.0.1:8080
