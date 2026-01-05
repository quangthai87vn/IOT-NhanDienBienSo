#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ffmpeg -re -stream_loop -1 -i "/Users/mtl/Documents/Video xe chay/d1.mov" \
  -vf "scale=640:480,fps=30" -an \
  -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
  -profile:v baseline -level 3.1 \
  -x264-params "bframes=0:keyint=30:min-keyint=30:scenecut=0" \
  -g 30 -r 30 -b:v 1500k -maxrate 1500k -bufsize 3000k \
  -f rtsp -rtsp_transport tcp "rtsp://192.168.50.2:8554/mac"
