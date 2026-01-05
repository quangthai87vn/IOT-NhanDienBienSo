#!/usr/bin/env bash
NAME="alpr_cam"
pkill -f gst-launch-1.0 >/dev/null 2>&1 || true
docker stop "$NAME" >/dev/null 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true
sudo systemctl restart nvargus-daemon || true
echo "Stopped."

