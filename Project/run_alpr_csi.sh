#!/usr/bin/env bash
set -e

NAME="alpr_csi"
IMG="iot-buiquangthai:jetson-alpr-r32.7.1"
WORK="$HOME/IOT/Project"

# Nếu có container cũ còn sống -> stop luôn
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Fix camera hay bị kẹt (Argus)
pkill -f gst-launch-1.0 >/dev/null 2>&1 || true
sudo systemctl restart nvargus-daemon || true

# X11 cho docker vẽ cửa sổ
export DISPLAY=${DISPLAY:-:0}
xhost +local:root >/dev/null 2>&1 || true

cleanup() {
  echo "[STOP] stopping container..."
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Chạy container foreground (đóng terminal = stop luôn)
docker run --rm -it \
  --name "$NAME" \
  --runtime nvidia \
  --network host \
  --privileged \
  -e DISPLAY="$DISPLAY" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v /tmp/argus_socket:/tmp/argus_socket \
  -v "$WORK":/workspace/project \
  -w /workspace/project \
  "$IMG" bash -lc '
    cd Real-time-Auto-License-Plate-Recognition-with-Jetson-Nano
    python3 detectnet-camera.py \
      --model=./networks/az_plate/az_plate_ssdmobilenetv1.onnx \
      --class_labels=./networks/az_plate/labels.txt \
      --input_blob=input_0 \
      --output_cvg=scores --output_bbox=boxes \
      --camera="csi://0?sensor-mode=2&framerate=30&flip-method=1" \
      --width=640 --height=480
  '

