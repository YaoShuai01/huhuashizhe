# -*- coding: utf-8 -*-
"""
飞控桥 UDP H.264 预览

电脑先连飞控热点 HuHuaShiZhe-Drone，再运行本脚本。
UDP 8889 收飞控转发的 H.264 分段，PyAV 解码后转 MJPEG：http://127.0.0.1:8004
"""
import io
import socket
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import av
from PIL import Image

HTTP_PORT = 8004
UDP_PORT = 8889

lock = threading.Lock()
state = {"jpg": None, "fps": 0.0, "mbps": 0.0, "status": "等待飞控 UDP 8889 数据...", "size": ""}

frames = {}
codec = av.CodecContext.create("h264", "r")
codec.open()


def feed_nal(data):
    try:
        for pkt in codec.parse(data):
            for frame in codec.decode(pkt):
                img = Image.fromarray(frame.to_ndarray(format="rgb24"))
                out = io.BytesIO()
                img.save(out, "JPEG", quality=85)
                with lock:
                    state["jpg"] = out.getvalue()
                    state["size"] = "%dx%d" % (img.width, img.height)
                    state["status"] = "飞控图传运行中"
    except Exception as e:
        with lock:
            state["status"] = "解码异常：%s" % e


def udp_worker():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", UDP_PORT))
    s.settimeout(0.2)

    cnt = 0
    nbytes = 0
    t0 = time.time()

    while True:
        try:
            pkt, addr = s.recvfrom(2048)
        except socket.timeout:
            pkt = None
            addr = None
        except Exception as e:
            with lock:
                state["status"] = "UDP 异常：%s" % e
            time.sleep(0.5)
            continue

        if pkt and len(pkt) >= 18 and pkt[0:2] == b"HV" and pkt[2] == 0x03:
            seq = int.from_bytes(pkt[3:7], "little")
            seg_idx = int.from_bytes(pkt[7:9], "little")
            seg_cnt = int.from_bytes(pkt[9:11], "little")
            nal_len = int.from_bytes(pkt[11:15], "little")
            seg_len = int.from_bytes(pkt[15:17], "little")
            data = pkt[18:18 + seg_len]
            nbytes += len(pkt)

            if 0 < nal_len <= 500000 and 0 < seg_cnt <= 1000 and seg_idx < seg_cnt:
                f = frames.get(seq)
                if f is None:
                    f = {"nal_len": nal_len, "seg_cnt": seg_cnt, "parts": {}, "t": time.time()}
                    frames[seq] = f
                f["parts"][seg_idx] = data
                if len(f["parts"]) == f["seg_cnt"]:
                    blob = b"".join(f["parts"][i] for i in range(f["seg_cnt"]))
                    frames.pop(seq, None)
                    if len(blob) >= 4:
                        feed_nal(blob)
                        cnt += 1
                        with lock:
                            state["status"] = "飞控图传运行中（%s）" % addr[0]

            now = time.time()
            if now - t0 >= 1.0:
                with lock:
                    state["fps"] = cnt / (now - t0)
                    state["mbps"] = nbytes * 8 / (now - t0) / 1e6
                cnt = 0
                nbytes = 0
                t0 = now

            if len(frames) > 30:
                oldest = sorted(frames.items(), key=lambda kv: kv[1]["t"])[:10]
                for k, _ in oldest:
                    frames.pop(k, None)


PAGE = """<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>护花使者 · 飞控桥 H.264 预览</title><style>
body{font-family:system-ui;background:#111;color:#eee;margin:0;padding:12px;text-align:center}
img{width:100%;max-width:1100px;border-radius:8px;background:#222}
p{color:#999;font-size:14px}
</style></head><body>
<h3>护花使者 · 飞控桥 H.264 实时预览</h3>
<img src='/stream'>
<p id='st'>__STATUS__</p>
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
                body = ("%s | %.1f fps | %.2f Mbps | %s"
                        % (state["status"], state["fps"], state["mbps"], state["size"])).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/":
            with lock:
                status = state["status"]
            body = PAGE.replace("__STATUS__", status).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    threading.Thread(target=udp_worker, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    print("浏览器打开 http://127.0.0.1:%d" % HTTP_PORT)
    threading.Timer(1.5, lambda: webbrowser.open("http://127.0.0.1:%d" % HTTP_PORT)).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
