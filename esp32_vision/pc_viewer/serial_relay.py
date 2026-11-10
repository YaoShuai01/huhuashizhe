# -*- coding: utf-8 -*-
"""
护花使者 · 视觉板串口图传 → 浏览器实时画面
USB 线直连电脑。双击 看图.bat 后自动打开浏览器即可看到实时画面。

依赖：仅 pyserial（IDF 自带 Python 环境已含，无需装任何东西）
协议见固件 vision_serial.h：VSS 开始 / VSE 停止，帧 'HV'+type+len32+JPEG
"""
import io
import os
import time
import struct
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import serial

PORT_NAME = "COM4"
BAUD_IDLE = 115200
BAUD_STREAM = 3000000
MAGIC = b"HV"
TYPE_LIVE = 0x03
MAX_FRAME = 3_500_000

lock = threading.Lock()
state = {"last_jpg": None, "fps": 0.0, "res": "", "status": "连接中...", "serial": None}


def serial_worker():
    ser = serial.Serial(PORT_NAME, BAUD_IDLE, timeout=0.1)
    ser.dtr = False
    ser.rts = False
    time.sleep(2.5)                    # 覆盖可能的复位
    ser.reset_input_buffer()
    state["status"] = "已连接 %s，正在启动实时画面..." % PORT_NAME

    # 启动实时流（失败自动重试）
    for _ in range(4):
        ser.reset_input_buffer()
        ser.write(b"VSS\n")
        buf = b""
        t0 = time.time()
        while time.time() - t0 < 3:
            buf += ser.read(128)
            if b"VOK SS" in buf:
                break
        if b"VOK SS" in buf:
            ser.baudrate = BAUD_STREAM
            ser.reset_input_buffer()
            break
        time.sleep(3)
    else:
        state["status"] = "启动失败：未收到板子应答，请拔插一次USB线后重开本窗口"
        return

    state["status"] = "实时画面运行中（3M 波特率）"

    # 帧解析循环
    buf = bytearray()
    fps_n = 0
    fps_t0 = time.time()
    while True:
        chunk = ser.read(8192)
        if chunk:
            buf += chunk
        while True:
            i = buf.find(MAGIC)
            if i < 0:
                del buf[:max(0, len(buf) - 1)]
                break
            if len(buf) - i < 8:
                del buf[:i]
                break
            ftype = buf[i + 2]
            (flen,) = struct.unpack("<I", bytes(buf[i + 3:i + 7]))
            if flen <= 0 or flen > MAX_FRAME or ftype != TYPE_LIVE:
                del buf[:i + 1]
                continue
            if len(buf) - i < 8 + flen:
                del buf[:i]
                break
            jpg = bytes(buf[i + 8:i + 8 + flen])
            del buf[:i + 8 + flen]
            with lock:
                state["last_jpg"] = jpg
            fps_n += 1
            now = time.time()
            if now - fps_t0 >= 1:
                with lock:
                    state["fps"] = fps_n / (now - fps_t0)
                    try:
                        from PIL import Image  # 仅读尺寸，缺pillow也不影响看画面
                    except ImportError:
                        pass
                fps_n = 0
                fps_t0 = now


PAGE = """<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>护花使者 · 视觉板图传</title><style>
body{{font-family:system-ui;background:#111;color:#eee;margin:0;padding:12px;text-align:center}}
img{{width:100%;max-width:900px;border-radius:8px;background:#333}}
p{{color:#999;font-size:13px}}
a.btn{{display:inline-block;margin:6px;padding:10px 20px;background:#5b6cff;color:#fff;
border-radius:8px;text-decoration:none;font-size:15px}}
</style></head><body>
<h3>护花使者 · 视觉板实时画面</h3>
<img src='/stream'>
<div><a class='btn' href='/save'>保存当前画面</a>
<a class='btn' href='javascript:location.reload()'>刷新</a></div>
<p>{status} | {fps:.1f} fps | 保存的照片在浏览器下载里</p>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send_jpeg(self, jpg, download=False):
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(jpg)))
        if download:
            self.send_header("Content-Disposition",
                             "attachment; filename=huhuashizhe_%d.jpg" % int(time.time()))
        self.end_headers()
        self.wfile.write(jpg)

    def do_GET(self):
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type",
                             "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            try:
                while True:
                    with lock:
                        jpg = state["last_jpg"]
                    if jpg:
                        part = (b"--frame\r\nContent-Type: image/jpeg\r\n"
                                b"Content-Length: " + str(len(jpg)).encode()
                                + b"\r\n\r\n")
                        self.wfile.write(part)
                        self.wfile.write(jpg)
                        self.wfile.write(b"\r\n")
                    time.sleep(0.08)   # ~12fps 刷新上限
            except (ConnectionAbortedError, BrokenPipeError, OSError):
                pass
        elif self.path == "/save":
            with lock:
                jpg = state["last_jpg"]
            if jpg:
                self._send_jpeg(jpg, download=True)
        elif self.path == "/":
            with lock:
                html = PAGE.format(status=state["status"], fps=state["fps"])
            body = html.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    t = threading.Thread(target=serial_worker, daemon=True)
    t.start()
    srv = ThreadingHTTPServer(("127.0.0.1", 8000), Handler)
    print("浏览器即将打开 http://127.0.0.1:8000 （关闭本窗口即停止）")
    threading.Timer(2.0, lambda: webbrowser.open("http://127.0.0.1:8000")).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
