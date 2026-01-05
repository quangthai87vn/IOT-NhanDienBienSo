#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"




ffmpeg -re -stream_loop -1 -i "/Users/mtl/Documents/Video xe chay/detect.mov" \
  -vf "scale=1280:720" \
  -c:v libx264 -preset veryfast -tune zerolatency \
  -crf 18 -maxrate 6M -bufsize 12M \
  -g 30 -r 30 -pix_fmt yuv420p \
  -an \
  -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/mac
