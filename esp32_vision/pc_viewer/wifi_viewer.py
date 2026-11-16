# -*- coding: utf-8 -*-
"""
护花使者 · 视觉板 WiFi 图传接收端（电脑用）

协议见固件 vision_udp.h（端口 8889，22 字节分段头 + 每 8 段一个 XOR 校验段）。
功能与 USB 版对齐：实时画面、保存、5MP 拍照、水平/垂直翻转、分辨率/画质切换。

用法：
    python wifi_viewer.py 192.168.5.210 [res] [fps] [q]
浏览器打开 http://127.0.0.1:8001
"""
import socket
import struct
import sys
import threading
import time
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

BOARD_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.6.1"
BOARD_PORT = 8889
HTTP_PORT = 8001
MAGIC = b"HV"
HDR = 22
SEG_MAX = 1400
FEC_GROUP = 8
FLAG_START = 0x01
FLAG_FEC = 0x02
MAX_FRAME = 3_500_000

RES = int(sys.argv[2]) if len(sys.argv) > 2 else 3
FPS = int(sys.argv[3]) if len(sys.argv) > 3 else 30
Q = int(sys.argv[4]) if len(sys.argv) > 4 else 12

lock = threading.Lock()
state = {
    "last_jpg": None,
    "snap_jpg": None,
    "fps": 0.0,
    "mbps": 0.0,
    "drops": 0,
    "status": "启动中...",
    "res": RES,
    "q": Q,
}

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 0))
sock.settimeout(0.2)


def send_cmd(text):
    try:
        sock.sendto(text.encode(), (BOARD_IP, BOARD_PORT))
    except Exception:
        pass


class FrameBuf:
    __slots__ = ("segs", "fec", "seg_cnt", "total", "ts", "is_photo")

    def __init__(self, seg_cnt, total, is_photo):
        self.segs = [None] * seg_cnt
        self.fec = {}
        self.seg_cnt = seg_cnt
        self.total = total
        self.ts = time.time()
        self.is_photo = is_photo

    def fill_from_fec(self):
        """每组缺 1 段时用 XOR 校验段恢复"""
        groups = (self.seg_cnt + FEC_GROUP - 1) // FEC_GROUP
        for g in range(groups):
            lo = g * FEC_GROUP
            hi = min(lo + FEC_GROUP, self.seg_cnt)
            missing = [i for i in range(lo, hi) if self.segs[i] is None]
            if len(missing) != 1 or g not in self.fec:
                continue
            acc = bytearray(self.fec[g])
            for i in range(lo, hi):
                if i == missing[0]:
                    continue
                pay = self.segs[i]
                for k in range(len(pay)):
                    acc[k] ^= pay[k]
            idx = missing[0]
            real = SEG_MAX if idx < self.seg_cnt - 1 else (
                self.total - (self.seg_cnt - 1) * SEG_MAX)
            self.segs[idx] = bytes(acc[:max(0, real)])

    def complete(self):
        return all(s is not None for s in self.segs)

    def join(self):
        return b"".join(self.segs)


def rx_loop():
    frames = {}
    win_frames = 0
    win_bytes = 0
    t0 = time.time()

    while True:
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            now = time.time()
            for k in [k for k, v in frames.items() if now - v.ts > 1.5]:
                del frames[k]
                with lock:
                    state["drops"] += 1
            continue
        except OSError:
            break

        if len(data) < HDR or data[:2] != MAGIC:
            txt = data[:80].decode("utf-8", "replace").strip()
            if txt.startswith("VOK") or txt.startswith("VERR"):
                with lock:
                    state["status"] = txt
            continue

        ftype = data[2]
        flags = data[3]
        photo_id, frame_seq = struct.unpack("<II", data[4:12])
        seg_idx, seg_cnt = struct.unpack("<HH", data[12:16])
        total_len, seg_len = struct.unpack("<IH", data[16:22])
        if total_len <= 0 or total_len > MAX_FRAME or seg_len > len(data) - HDR:
            continue
        if seg_cnt == 0 or seg_idx >= seg_cnt:
            continue

        key = (ftype, photo_id, frame_seq)
        ent = frames.get(key)
        if ent is None:
            ent = FrameBuf(seg_cnt, total_len, ftype == 0x02)
            frames[key] = ent
        ent.ts = time.time()
        payload = data[HDR:HDR + seg_len]
        if flags & FLAG_FEC:
            ent.fec[seg_idx] = payload        # 校验段：seg_idx 是组号
            continue
        ent.segs[seg_idx] = payload

        if not ent.complete():
            ent.fill_from_fec()
        if not ent.complete():
            continue

        jpg = ent.join()
        del frames[key]
        if not jpg.startswith(b"\xff\xd8"):
            continue
        if ent.is_photo:
            with lock:
                state["snap_jpg"] = jpg
        else:
            win_frames += 1
            win_bytes += len(jpg)
            with lock:
                state["last_jpg"] = jpg

        now = time.time()
        if now - t0 >= 1.0:
            with lock:
                state["fps"] = win_frames / (now - t0)
                state["mbps"] = win_bytes * 8 / (now - t0) / 1e6
            win_frames = 0
            win_bytes = 0
            t0 = now


PAGE = """<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>护花使者 · WiFi 图传</title><style>
body{{font-family:system-ui;background:#111;color:#eee;margin:0;padding:12px;text-align:center}}
img{{width:100%;max-width:1000px;border-radius:8px;background:#333}}
p{{color:#999;font-size:14px}}
a.btn{{display:inline-block;margin:6px;padding:10px 20px;background:#5b6cff;color:#fff;
border-radius:8px;text-decoration:none;font-size:15px}}
select{{background:#222;color:#eee;border:1px solid #444;border-radius:6px;
padding:7px 10px;font-size:14px;margin:0 6px}}
</style></head><body>
<h3>护花使者 · WiFi 图传（{board}）</h3>
<img src='/stream'>
<div><a class='btn' href='/save'>保存当前画面</a>
<a class='btn' href='/snap'>5MP 拍照 (2560x1920)</a>
<a class='btn' id='btnH' href='javascript:flip("h")'>水平翻转: 关</a>
<a class='btn' id='btnV' href='javascript:flip("v")'>垂直翻转: 关</a>
</div>
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
<p>{status} | {fps:.1f} fps | {mbps:.2f} Mbps | 丢帧 {drops}</p>
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
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            try:
                while True:
                    with lock:
                        jpg = state["last_jpg"]
                    if jpg:
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n"
                                         b"Content-Length: " + str(len(jpg)).encode() + b"\r\n\r\n")
                        self.wfile.write(jpg)
                        self.wfile.write(b"\r\n")
                    time.sleep(0.03)
            except (ConnectionAbortedError, BrokenPipeError, OSError):
                pass
        elif self.path == "/save":
            with lock:
                jpg = state["last_jpg"]
            if jpg:
                self._send_jpeg(jpg, download=True)
            else:
                self.send_response(503)
                self.end_headers()
        elif self.path == "/snap":
            # 5MP 大图走板子的 HTTP /capture（TCP 可靠），
            # 不走 UDP：400KB 要拆 286 段突发，sendto 会因缓冲耗尽直接失败
            jpg = None
            try:
                with urllib.request.urlopen(
                        "http://%s/capture?res=7" % BOARD_IP, timeout=25) as r:
                    jpg = r.read()
            except Exception:
                jpg = None
            if jpg and jpg.startswith(b"\xff\xd8"):
                self._send_jpeg(jpg, download=True)
            else:
                self.send_response(504)
                self.end_headers()
        elif self.path.startswith("/flip"):
            qp = parse_qs(urlparse(self.path).query)
            h = 1 if qp.get("h", ["0"])[0] == "1" else 0
            v = 1 if qp.get("v", ["0"])[0] == "1" else 0
            send_cmd("VMIR %d" % h)
            send_cmd("VFLIP %d" % v)
            self.send_response(204)
            self.end_headers()
        elif self.path.startswith("/set"):
            qp = parse_qs(urlparse(self.path).query)
            try:
                if "q" in qp:                 # 先更新画质，VSTART 才会带上新值
                    state["q"] = max(6, min(25, int(qp["q"][0])))
                if "res" in qp:
                    state["res"] = max(0, min(5, int(qp["res"][0])))
                    send_cmd("VSTART %d %d %d" % (state["res"], FPS, state["q"]))
                elif "q" in qp:
                    send_cmd("VSET %d %d" % (FPS, state["q"]))
            except Exception:
                pass
            self.send_response(204)
            self.end_headers()
        elif self.path == "/":
            with lock:
                html = PAGE.format(board=BOARD_IP, status=state["status"],
                                   fps=state["fps"], mbps=state["mbps"],
                                   drops=state["drops"], res=state["res"], q=state["q"])
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
    print("目标: %s:%d  参数: res=%d fps=%d q=%d" % (BOARD_IP, BOARD_PORT, RES, FPS, Q), flush=True)
    threading.Thread(target=rx_loop, daemon=True).start()
    time.sleep(0.5)
    send_cmd("VSTART %d %d %d" % (RES, FPS, Q))
    srv = ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    print("浏览器打开 http://127.0.0.1:%d （Ctrl+C 停止）" % HTTP_PORT, flush=True)
    threading.Timer(1.5, lambda: webbrowser.open("http://127.0.0.1:%d" % HTTP_PORT)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        send_cmd("VSTOP")
        print("已发送 VSTOP", flush=True)


if __name__ == "__main__":
    main()
