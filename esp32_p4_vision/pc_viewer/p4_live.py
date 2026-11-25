# -*- coding: utf-8 -*-
"""
ESP32-P4 实时预览（原生 USB-Serial-JTAG）

固件协议：'H''V' + type(1) + len32(LE) + JPEG
浏览器打开 http://127.0.0.1:8002
"""
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import serial
from serial.tools import list_ports

HTTP_PORT = 8002
MAX_FRAME = 5_000_000

lock = threading.Lock()
state = {"jpg": None, "fps": 0.0, "status": "等待 P4 USB 口...", "h264": "检测中..."}


def find_port():
    for p in list_ports.comports():
        if p.vid == 0x303A:
            return p.device
    return None


def serial_worker():
    while True:
        port = find_port()
        if not port:
            with lock:
                state["status"] = "未找到 P4 原生 USB 口（VID 303A），请插板子上的 Type-C USB 口"
            time.sleep(1.0)
            continue

        try:
            ser = serial.Serial(port, 115200, timeout=0.2)
        except Exception as e:
            with lock:
                state["status"] = "打开 %s 失败：%s" % (port, e)
            time.sleep(1.0)
            continue

        try:
            ser.dtr = False
            ser.rts = False
        except Exception:
            pass

        with lock:
            state["status"] = "已连接 %s，等待画面..." % port

        buf = bytearray()
        cnt = 0
        t0 = time.time()

        try:
            while True:
                chunk = ser.read(8192)
                if chunk:
                    buf += chunk

                # H.264 自检结果文本行
                hi = buf.find(b"H264STAT ")
                if hi >= 0:
                    nl = buf.find(b"\n", hi)
                    if nl > hi:
                        txt = bytes(buf[hi + 9:nl]).decode("utf-8", "replace").strip()
                        with lock:
                            state["h264"] = txt
                        del buf[:nl + 1]

                while True:
                    i = buf.find(b"HV")
                    if i < 0:
                        if len(buf) > 1:
                            del buf[:-1]
                        break
                    if len(buf) - i < 8:
                        del buf[:i]
                        break
                    ln = int.from_bytes(buf[i + 3:i + 7], "little")
                    if ln <= 0 or ln >= MAX_FRAME:
                        del buf[i:i + 1]
                        continue
                    if len(buf) - i < 8 + ln:
                        del buf[:i]
                        break

                    jpg = bytes(buf[i + 8:i + 8 + ln])
                    del buf[:i + 8 + ln]
                    with lock:
                        state["jpg"] = jpg
                        state["status"] = "实时画面运行中（%s）" % port
                    cnt += 1

                now = time.time()
                if now - t0 >= 1.0:
                    with lock:
                        state["fps"] = cnt / (now - t0)
                    cnt = 0
                    t0 = now

                if len(buf) > 20 * MAX_FRAME:
                    del buf[:-8192]
        except Exception as e:
            with lock:
                state["status"] = "串口断开：%s，重试中..." % e
            try:
                ser.close()
            except Exception:
                pass
            time.sleep(1.0)


PAGE = """<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>护花使者 · P4 实时预览</title><style>
body{font-family:system-ui;background:#111;color:#eee;margin:0;padding:12px;text-align:center}
img{width:100%;max-width:1100px;border-radius:8px;background:#222}
p{color:#999;font-size:14px}
</style></head><body>
<h3>护花使者 · ESP32-P4 实时预览</h3>
<img src='/stream'>
<p id='st'>__STATUS__ | H.264: __H264__</p>
<script>
setInterval(function(){fetch('/status').then(r=>r.text()).then(t=>{document.getElementById('st').textContent=t})},1000);
</script>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            last = None
            try:
                while True:
                    with lock:
                        jpg = state["jpg"]
                    if jpg is not None and jpg is not last:
                        last = jpg
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                                         + str(len(jpg)).encode() + b"\r\n\r\n")
                        self.wfile.write(jpg)
                        self.wfile.write(b"\r\n")
                    time.sleep(0.02)
            except (BrokenPipeError, ConnectionAbortedError, OSError):
                pass
        elif self.path == "/status":
            with lock:
                body = ("%s | %.1f fps | H.264: %s"
                        % (state["status"], state["fps"], state["h264"])).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/":
            with lock:
                status = state["status"]
                h264 = state["h264"]
            body = PAGE.replace("__STATUS__", status).replace("__H264__", h264).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    threading.Thread(target=serial_worker, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    print("浏览器打开 http://127.0.0.1:%d" % HTTP_PORT)
    threading.Timer(1.5, lambda: webbrowser.open("http://127.0.0.1:%d" % HTTP_PORT)).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
