#!/usr/bin/env bash
# Chạy mỗi lần Codespace khởi động: bật Flask ở cổng 5000.
cd "$(dirname "$0")/../demo_app"
pkill -f "flask --app app" 2>/dev/null || true
nohup flask --app app run --host 0.0.0.0 --port 5000 > /tmp/flask.log 2>&1 &
