#!/usr/bin/env bash
set -e

NAME="alpr_cam"
IMG="iot-buiquangthai:jetson-alpr-r32.7.1"
WORK="$HOME/IOT/Project"
APPDIR="Real-time-Auto-License-Plate-Recognition-with-Jetson-Nano"

MODE="${1:-csi}"   # csi | rtsp
RTSP_URL="${2:-rtsp://192.168.50.2:8554/mac}"

WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
SENSOR_MODE="${SENSOR_MODE:-2}"
FLIP="${FLIP:-0}"  # 0 bình thường, 2 xoay 180

# clear + reset camera
docker rm -f "$NAME" >/dev/null 2>&1 || true
pkill -f gst-launch-1.0 >/dev/null 2>&1 || true
sudo systemctl restart nvargus-daemon || true

# X11
export DISPLAY=${DISPLAY:-:0}
xhost +local:root >/dev/null 2>&1 || true

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if [[ "$MODE" == "csi" ]]; then
  CAM_ARG="csi://0?sensor-mode=${SENSOR_MODE}&framerate=${FPS}&flip-method=${FLIP}"
  EXTRA_ARGS=""
elif [[ "$MODE" == "rtsp" ]]; then
  CAM_ARG="${RTSP_URL}"
  EXTRA_ARGS="--input-codec=h264"
else
  echo "Usage:"
  echo "  $0 csi"
  echo "  $0 rtsp rtsp://ip:port/path"
  exit 1
fi

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
      --model=./networks/az_plate/az_plate_ssdmobilenetv1.onnx \
      --class_labels=./networks/az_plate/labels.txt \
      --input_blob=input_0 \
      --output_cvg=scores --output_bbox=boxes \
      --camera='$CAM_ARG' \
      --width=$WIDTH --height=$HEIGHT \
      $EXTRA_ARGS
  "

