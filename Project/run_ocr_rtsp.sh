#!/usr/bin/env bash
set -e

NAME="alpr_ocr"
IMG="iot-buiquangthai:jetson-alpr-r32.7.1"
WORK="$HOME/IOT/Project"
APPDIR="Real-time-Auto-License-Plate-Recognition-with-Jetson-Nano"

RTSP_URL="${1:-rtsp://192.168.50.2:8554/mac}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
LAT="${LAT:-500}"

# clear
docker rm -f "$NAME" >/dev/null 2>&1 || true
pkill -f gst-launch-1.0 >/dev/null 2>&1 || true

# X11
export DISPLAY=${DISPLAY:-:0}
xhost +local:root >/dev/null 2>&1 || true

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

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
  "$IMG" bash -lc "
    cd $APPDIR
    python3 detectnet-camera.py \
      --model=./networks/az_ocr/az_ocr_ssdmobilenetv1_2.onnx \
      --class_labels=./networks/az_ocr/labels.txt \
      --input_blob=input_0 \
      --output_cvg=scores --output_bbox=boxes \
      --camera='$RTSP_URL' \
      --input-codec=h264 \
      --width=$WIDTH --height=$HEIGHT \
      --input-rtsp-latency=$LAT
  "

