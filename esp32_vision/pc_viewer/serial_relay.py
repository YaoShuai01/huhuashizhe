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
from urllib.parse import urlparse, parse_qs

import serial
from serial.tools import list_ports

PORT_NAME = "COM3"          # 回退端口（自动识别失败时使用）
BAUD_IDLE = 115200
BAUD_STREAM = 3000000
MAGIC = b"HV"
TYPE_LIVE = 0x03
TYPE_SNAP = 0x04
MAX_FRAME = 3_500_000

lock = threading.Lock()
state = {"last_jpg": None, "snap_jpg": None, "fps": 0.0, "res": 3, "q": 12,
         "status": "连接中...", "serial": None}


def find_port():
    """优先选 ESP32-S3 原生 USB（VID 303A）；找不到再用回退端口。"""
    ports = list(list_ports.comports())
    for p in ports:
        if p.vid == 0x303A:
            return p.device
    for p in ports:
        if PORT_NAME and p.device.upper() == PORT_NAME.upper():
            return p.device
    return PORT_NAME


def serial_worker():
    port = find_port()
    try:
        ser = serial.Serial(port, BAUD_IDLE, timeout=0.1)
    except Exception as e:
        state["status"] = "打开 %s 失败：%s（请确认 USB 线已插好）" % (port, e)
        return
    try:
        ser.dtr = False
        ser.rts = False
    except Exception:
        pass
    with lock:
        state["serial"] = ser
    time.sleep(2.5)                    # 覆盖可能的复位
    ser.reset_input_buffer()
    state["status"] = "已连接 %s，正在启动实时画面..." % port

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
            try:
                ser.baudrate = BAUD_STREAM   # USB CDC 无实际波特率，失败也不影响
            except Exception:
                pass
            time.sleep(0.2)
            ser.reset_input_buffer()
            break
        time.sleep(3)
    else:
        state["status"] = "启动失败：%s 未应答，请拔插一次USB线后重开本窗口" % port
        return

    state["status"] = "实时画面运行中（USB 直连 %s）" % port

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
            if flen <= 0 or flen > MAX_FRAME or ftype not in (TYPE_LIVE, TYPE_SNAP):
                del buf[:i + 1]
                continue
            if len(buf) - i < 8 + flen:
                del buf[:i]
                break
            jpg = bytes(buf[i + 8:i + 8 + flen])
            del buf[:i + 8 + flen]
            with lock:
                if ftype == TYPE_SNAP:
                    state["snap_jpg"] = jpg
                else:
                    state["last_jpg"] = jpg
            if ftype == TYPE_LIVE:
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
select{{background:#222;color:#eee;border:1px solid #444;border-radius:6px;
padding:7px 10px;font-size:14px;margin:0 6px}}
</style></head><body>
<h3>护花使者 · 视觉板实时画面</h3>
<img src='/stream'>
<div><a class='btn' href='/save'>保存当前画面</a>
<a class='btn' href='/snap'>5MP 拍照 (2560x1920)</a>
<a class='btn' id='btnH' href='javascript:flip("h")'>水平翻转: 关</a>
<a class='btn' id='btnV' href='javascript:flip("v")'>垂直翻转: 关</a>
<a class='btn' href='javascript:location.reload()'>刷新</a></div>
<div style='margin:10px 0'>分辨率
<select id='selRes' onchange='setp()'>
<option value='0'>VGA 640x480</option>
<option value='1'>SVGA 800x600</option>
<option value='2'>XGA 1024x768</option>
<option value='3'>HD 1280x720</option>
<option value='4'>SXGA 1280x1024</option>
<option value='5'>UXGA 1600x1200</option>
</select>
画质
<select id='selQ' onchange='setp()'>
<option value='8'>高</option>
<option value='10'>较高</option>
<option value='12'>标准</option>
<option value='18'>流畅</option>
<option value='22'>省流</option>
<option value='25'>极省流</option>
</select>
<span id='hint' style='color:#7fd67f'></span></div>
<p>{status} | {fps:.1f} fps | 保存的照片在浏览器下载里</p>
<script>
var st = {{h:0, v:0}};
document.getElementById('selRes').value = '{res}';
document.getElementById('selQ').value = '{q}';
function flip(k) {{
  st[k] = st[k] ? 0 : 1;
  document.getElementById('btnH').textContent = '水平翻转: ' + (st.h ? '开' : '关');
  document.getElementById('btnV').textContent = '垂直翻转: ' + (st.v ? '开' : '关');
  fetch('/flip?h=' + st.h + '&v=' + st.v);
}}
function setp() {{
  var r = document.getElementById('selRes').value;
  var q = document.getElementById('selQ').value;
  fetch('/set?res=' + r + '&q=' + q);
  document.getElementById('hint').textContent = '已切换，约1秒后生效';
}}
</script>
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
        elif self.path.startswith("/set"):
            q = parse_qs(urlparse(self.path).query)
            with lock:
                ser = state.get("serial")
            if ser is not None:
                try:
                    if "res" in q:
                        r = max(0, min(5, int(q["res"][0])))
                        state["res"] = r
                        ser.write(("VRES %d\n" % r).encode())
                    if "q" in q:
                        qq = max(6, min(25, int(q["q"][0])))
                        state["q"] = qq
                        ser.write(("VQ %d\n" % qq).encode())
                except Exception:
                    pass
            self.send_response(204)
            self.end_headers()
        elif self.path.startswith("/flip"):
            q = parse_qs(urlparse(self.path).query)
            h = 1 if q.get("h", ["0"])[0] == "1" else 0
            v = 1 if q.get("v", ["0"])[0] == "1" else 0
            with lock:
                ser = state.get("serial")
            if ser is not None:
                try:
                    ser.write(("HMIRROR %d\n" % h).encode())
                    ser.write(("VFLIP %d\n" % v).encode())
                except Exception:
                    pass
            self.send_response(204)
            self.end_headers()
        elif self.path == "/snap":
            with lock:
                ser = state.get("serial")
                state["snap_jpg"] = None
            if ser is None:
                self.send_response(503)
                self.end_headers()
                return
            try:
                ser.write(b"VS2\n")          # QSXGA 2560x1920 单张拍照
            except Exception:
                self.send_response(500)
                self.end_headers()
                return
            jpg = None
            t0 = time.time()
            while time.time() - t0 < 15:     # 5MP 编码+传输约需 1~3 秒
                with lock:
                    jpg = state["snap_jpg"]
                    if jpg:
                        state["snap_jpg"] = None
                if jpg:
                    break
                time.sleep(0.1)
            # 拍照后传感器可能停在过渡尺寸，重新下发推流参数确保恢复
            try:
                ser.write(("VRES %d\n" % state["res"]).encode())
                ser.write(("VQ %d\n" % state["q"]).encode())
            except Exception:
                pass
            if jpg:
                self._send_jpeg(jpg, download=True)
            else:
                self.send_response(504)
                self.end_headers()
        elif self.path == "/save":
            with lock:
                jpg = state["last_jpg"]
            if jpg:
                self._send_jpeg(jpg, download=True)
        elif self.path == "/":
            with lock:
                html = PAGE.format(status=state["status"], fps=state["fps"],
                                   res=state["res"], q=state["q"])
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
