#!/usr/bin/env bash
NAME="alpr_csi"

echo "[STOP] killing gst-launch + stopping docker..."
pkill -f gst-launch-1.0 >/dev/null 2>&1 || true
docker stop "$NAME" >/dev/null 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "[STOP] restart nvargus-daemon (camera reset)"
sudo systemctl restart nvargus-daemon || true
echo "DONE"

