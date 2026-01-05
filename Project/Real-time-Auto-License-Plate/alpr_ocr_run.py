#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import argparse

import jetson_inference
import jetson_utils


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def try_cuda_crop(img, left, top, right, bottom):
    """
    Compatibility crop for different jetson_utils versions.
    Returns a cudaImage ROI.
    """
    # Ensure ints
    left, top, right, bottom = int(left), int(top), int(right), int(bottom)

    # Try signature A: cudaCrop(img, (l,t,r,b))
    try:
        return jetson_utils.cudaCrop(img, (left, top, right, bottom))
    except Exception:
        pass

    # Try signature B: cudaCrop(img, output, l,t,r,b)
    try:
        w = max(1, right - left)
        h = max(1, bottom - top)
        roi = jetson_utils.cudaAllocMapped(width=w, height=h, format=img.format)
        jetson_utils.cudaCrop(img, roi, left, top, right, bottom)
        return roi
    except Exception as e:
        raise RuntimeError(f"cudaCrop failed with this jetson_utils build: {e}")


def build_input_argv(args):
    argv = []

    # jetson_utils.videoSource uses these style flags:
    # --input-width --input-height --input-codec --input-rtsp-latency
    if args.width:
        argv += [f"--input-width={args.width}"]
    if args.height:
        argv += [f"--input-height={args.height}"]

    if args.input_codec:
        argv += [f"--input-codec={args.input_codec}"]

    if args.input_rtsp_latency is not None:
        argv += [f"--input-rtsp-latency={args.input_rtsp_latency}"]

    # optional flip (some builds support --input-flip)
    if args.input_flip is not None and args.input_flip != "":
        argv += [f"--input-flip={args.input_flip}"]

    return argv


def build_output_argv(args):
    argv = []
    if args.show_fps:
        argv += ["--show-fps"]
    return argv


def overlay_to_string(overlay):
    """
    overlay can be:
      - "" (none)
      - "box"
      - "box,labels,conf"
    """
    if overlay is None:
        return "box,labels,conf"
    return overlay.strip()


def get_plate_text(ocr_net, char_dets):
    """
    Sort chars left->right and build string by class labels.
    """
    if not char_dets:
        return ""

    # sort by center-x
    char_dets = sorted(char_dets, key=lambda d: float(d.Center[0]))

    chars = []
    for d in char_dets:
        label = ocr_net.GetClassDesc(int(d.ClassID))
        if label is None:
            continue
        label = label.strip()

        # common cleanup
        if label.lower() in ["space", "blank", "_"]:
            continue
        if label.lower() in ["dash", "hyphen"]:
            label = "-"
        chars.append(label)

    text = "".join(chars)

    # optional: remove weird spaces
    text = text.replace(" ", "").strip()
    return text


def main():
    parser = argparse.ArgumentParser(
        description="ALPR OCR (plate detect + OCR detect) for CSI/RTSP using jetson-inference",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )

    # Source / Display
    parser.add_argument("--camera", "--source", dest="camera", required=True,
                        help='Input source. Examples: "csi://0?sensor-mode=2&framerate=30" or "rtsp://192.168.50.2:8554/mac"')
    parser.add_argument("--display", default="display://0", help='Output display URI (or "file://out.mp4")')

    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)

    parser.add_argument("--input-codec", dest="input_codec", default="", help="For RTSP: h264/h265 (leave empty for auto)")
    parser.add_argument("--input-rtsp-latency", type=int, default=500, help="RTSP latency (ms)")
    parser.add_argument("--input-flip", default="", help='Optional input flip (if supported): "rotate-180", "none", ...')

    parser.add_argument("--show-fps", action="store_true", help="Show FPS on display status")

    # Plate detect model
    parser.add_argument("--plate-model", default="./networks/az_plate/az_plate_ssdmobilenetv1.onnx")
    parser.add_argument("--plate-labels", default="./networks/az_plate/labels.txt")
    parser.add_argument("--plate-input-blob", default="input_0")
    parser.add_argument("--plate-output-cvg", default="scores")
    parser.add_argument("--plate-output-bbox", default="boxes")
    parser.add_argument("--plate-threshold", type=float, default=0.5)

    # OCR model
    parser.add_argument("--ocr-model", default="./networks/az_ocr/az_ocr_ssdmobilenetv1_2.onnx")
    parser.add_argument("--ocr-labels", default="./networks/az_ocr/labels.txt")
    parser.add_argument("--ocr-input-blob", default="input_0")
    parser.add_argument("--ocr-output-cvg", default="scores")
    parser.add_argument("--ocr-output-bbox", default="boxes")
    parser.add_argument("--ocr-threshold", type=float, default=0.35)

    # Overlay settings (STRING, not detectNet.OVERLAY_*)
    parser.add_argument("--overlay", default="box,labels,conf",
                        help='Overlay for plate net: "", "box", "box,labels,conf"')
    parser.add_argument("--ocr-overlay", default="box,labels,conf",
                        help='Overlay for ocr net (on ROI): "", "box", "box,labels,conf"')

    parser.add_argument("--max-plates", type=int, default=1, help="Max plates to OCR per frame")
    parser.add_argument("--print-every", type=float, default=0.4, help="Throttle console prints (seconds)")

    args = parser.parse_args()

    # Build IO
    input_argv = build_input_argv(args)
    output_argv = build_output_argv(args)

    src = jetson_utils.videoSource(args.camera, argv=input_argv)
    out = jetson_utils.videoOutput(args.display, argv=output_argv)

    # Load networks
    plate_net = jetson_inference.detectNet(
        argv=[
            f"--model={args.plate_model}",
            f"--labels={args.plate_labels}",
            f"--input_blob={args.plate_input_blob}",
            f"--output_cvg={args.plate_output_cvg}",
            f"--output_bbox={args.plate_output_bbox}",
            f"--threshold={args.plate_threshold}",
        ]
    )

    ocr_net = jetson_inference.detectNet(
        argv=[
            f"--model={args.ocr_model}",
            f"--labels={args.ocr_labels}",
            f"--input_blob={args.ocr_input_blob}",
            f"--output_cvg={args.ocr_output_cvg}",
            f"--output_bbox={args.ocr_output_bbox}",
            f"--threshold={args.ocr_threshold}",
        ]
    )

    plate_overlay = overlay_to_string(args.overlay)
    ocr_overlay = overlay_to_string(args.ocr_overlay)

    last_print_t = 0.0
    last_text = ""

    while out.IsStreaming() and src.IsStreaming():
        img = src.Capture()
        if img is None:
            continue

        # Plate detection (overlay string)
        plates = plate_net.Detect(img, overlay=plate_overlay)

        # Sort plates by area desc
        plates = sorted(plates, key=lambda d: float(d.Area), reverse=True)

        texts = []
        for det in plates[: max(1, args.max_plates)]:
            l = clamp(int(det.Left), 0, img.width - 1)
            t = clamp(int(det.Top), 0, img.height - 1)
            r = clamp(int(det.Right), 0, img.width - 1)
            b = clamp(int(det.Bottom), 0, img.height - 1)

            if r - l < 10 or b - t < 10:
                continue

            roi = try_cuda_crop(img, l, t, r, b)

            # OCR detect on cropped plate region
            char_dets = ocr_net.Detect(roi, overlay=ocr_overlay)
            text = get_plate_text(ocr_net, char_dets)

            if text:
                texts.append(text)

                # draw text on main image (best-effort)
                try:
                    jetson_utils.cudaDrawText(img, text, l, max(0, t - 20), (255, 255, 255, 255), (0, 0, 0, 160))
                except Exception:
                    pass

        # status & render
        status = "ALPR OCR"
        if texts:
            status += " | " + " | ".join(texts)
        out.SetStatus(status)
        out.Render(img)

        # console print (throttle)
        now = time.time()
        if texts:
            combined = " | ".join(texts)
            if (now - last_print_t) >= args.print_every and combined != last_text:
                print(f"[OCR] {combined}")
                last_print_t = now
                last_text = combined

    # cleanup
    out.Close()
    src.Close()


if __name__ == "__main__":
    main()

