#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
护花使者 · 视觉板验收工具（UDP 图传 + 实时调试数据）

为什么不用固件自带网页：网页走 TCP + MJPEG，实测只有 0.25fps，
测不出 UDP 主链路的真实性能。本脚本自己就是 UDP 客户端（端口 8889），
显示的是 App 会拿到的那条链路的真实数据。

用法：
    python3 vision_check.py                # 默认 192.168.5.1
    python3 vision_check.py 192.168.5.1    # 指定视觉板 IP

前置：电脑需连上视觉板热点（HuHuaShiZhe-CAM）或与板子同网段。
启动后自动打开 http://127.0.0.1:8890

依赖：仅标准库。JPEG 尺寸解析用内置实现（不依赖 Pillow）。
"""

import json
import socket
import struct
import sys
import threading
import time
import urllib.request
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ==================== 配置 ====================
UDP_PORT = 8889
HTTP_PORT = 8890
MAGIC = b"HV"

# 与固件 send_segments() 保持一致
SEG_MAX = 1400
FEC_GROUP = 8

# 与 App 的三个档位一致（res, fps, q）
PROFILES = [
    ("流畅", 2, 25, 15),   # XGA 1024x768
    ("均衡", 3, 15, 10),   # HD 1280x720
    ("高清", 5, 8, 9),     # UXGA 1600x1200
]

BOARD = sys.argv[1] if len(sys.argv) > 1 else "192.168.5.1"


# ==================== JPEG 尺寸解析（不依赖 Pillow）====================
def jpeg_size(b):
    """从 JPEG 数据里读 SOF 段拿宽高，失败返回 (0, 0)。"""
    try:
        i = 2
        n = len(b)
        while i < n - 9:
            if b[i] != 0xFF:
                i += 1
                continue
            m = b[i + 1]
            if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                     0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", b[i + 5:i + 9])
                return w, h
            if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7 or m == 0x01:
                i += 2
                continue
            (sl,) = struct.unpack(">H", b[i + 2:i + 4])
            i += 2 + sl
    except Exception:
        pass
    return 0, 0


# ==================== UDP 客户端 + FEC 重组 ====================
class UdpReceiver:
    def __init__(self, board):
        self.board = board
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
        self.sock.settimeout(0.25)

        self.lock = threading.Lock()
        self.latest_jpeg = None
        self.latest_w = 0
        self.latest_h = 0

        # 统计
        self.frames = deque()          # (timestamp, bytes)
        self.pkt_count = 0
        self.byte_count = 0
        self.fec_recovered = 0         # 靠 FEC 救回来的帧数
        self.frame_loss = 0           # 放弃的残缺帧数
        self.complete_frames = 0

        self.pending = {}              # seq -> dict(segments, fec, seg_cnt, total)
        self.done = set()              # 已完成的 seq，防止迟到分段重复计数
        self.last_seq = None           # 用于检测整帧丢失（seq 跳变）
        self.running = True
        self.streaming = False

        self._t = threading.Thread(target=self._loop, daemon=True)
        self._t.start()

    # ---------- 发送命令 ----------
    def send(self, cmd):
        try:
            self.sock.sendto(cmd.encode(), (self.board, UDP_PORT))
            return True
        except Exception:
            return False

    def vinfo(self, timeout=2.0):
        """探测板子是否在线并拿状态。"""
        t0 = time.time()
        while time.time() - t0 < timeout:
            self.send("VINFO")
            try:
                d, _ = self.sock.recvfrom(2048)
                if d[:3] == b"VOK":
                    return d.decode("utf-8", "replace").strip()
            except socket.timeout:
                continue
            except Exception:
                break
        return None

    def start_stream(self, res, fps, q):
        self.pending.clear()
        self.done.clear()
        self.last_seq = None
        self.send(f"VSTART {res} {fps} {q}")
        self.streaming = True

    def stop_stream(self):
        self.send("VSTOP")
        self.streaming = False

    # ---------- 收包循环 ----------
    def _loop(self):
        last_gc = time.time()
        while self.running:
            try:
                d, _ = self.sock.recvfrom(65535)
            except socket.timeout:
                last_gc = 0
                continue
            except Exception:
                break
            self._on_packet(d)
            # 每 0.3 秒清理一次超时帧；只靠 socket 超时触发会漏
            if time.time() - last_gc > 0.3:
                self._gc()
                last_gc = time.time()
        self._gc()

    def _gc(self):
        """清理超时未拼齐的帧（UDP 丢段）。
        注意：只统计真正残缺的帧，不要重复计数 —— 已完成的帧早就从
        pending 里移除了，这里剩下的都是没收齐的。"""
        now = time.time()
        for seq in [k for k, v in self.pending.items() if now - v["t0"] > 0.6]:
            p = self.pending.pop(seq)
            # 至少收到过分段才算是"本可完成却失败"的帧
            if p["segments"] and len(p["segments"]) < p["seg_cnt"]:
                self.frame_loss += 1

    def _on_packet(self, d):
        self.pkt_count += 1
        self.byte_count += len(d)

        if len(d) < 22 or d[:2] != MAGIC:
            # 文本应答（VOK/VERR）
            return

        ftype = d[2]
        flags = d[3]
        seq = struct.unpack("<I", d[8:12])[0]
        seg_idx, seg_cnt = struct.unpack("<HH", d[12:16])
        total_len = struct.unpack("<I", d[16:20])[0]
        seg_len = struct.unpack("<H", d[20:22])[0]

        if ftype != 0x01:            # 只处理推流帧，拍照帧忽略
            return
        if seg_cnt == 0 or seg_cnt > 4096:
            return
        if len(d) < 22 + seg_len:
            return

        # 已完成的帧不再计入（同一 seq 的迟到分段不重复统计）
        if seq in self.done:
            return

        p = self.pending.get(seq)
        if p is None:
            # 新帧起点：统计 seq 跳变 = 中间有帧整帧丢失
            if self.last_seq is not None:
                gap = (seq - self.last_seq) & 0xFFFFFFFF
                if 0 < gap <= 60:
                    self.frame_loss += gap - 1
            self.last_seq = seq
            p = {"segments": {}, "fec": {}, "seg_cnt": seg_cnt,
                 "total": total_len, "t0": time.time(), "used_fec": False}
            self.pending[seq] = p

        payload = d[22:22 + seg_len]
        if flags & 0x02:
            p["fec"][seg_idx] = payload
        else:
            p["segments"][seg_idx] = payload

        jpg = self._assemble(p)
        if jpg is None:
            return

        del self.pending[seq]
        self.done.add(seq)
        # done 集合只需保留最近一段，防止无限增长
        if len(self.done) > 512:
            self.done = set(list(self.done)[-256:])

        if p["used_fec"]:
            self.fec_recovered += 1
        self.complete_frames += 1

        now = time.time()
        self.frames.append((now, len(jpg)))
        while self.frames and now - self.frames[0][0] > 60:
            self.frames.popleft()

        w, h = jpeg_size(jpg)
        with self.lock:
            self.latest_jpeg = jpg
            if w:
                self.latest_w, self.latest_h = w, h

    def _assemble(self, p):
        """按 FEC 规则拼帧；允许用 XOR 校验段恢复【一个】丢失分段。"""
        cnt = p["seg_cnt"]
        segs = p["segments"]
        if len(segs) < cnt - 1:
            return None

        missing = None
        for i in range(cnt):
            if i not in segs:
                if missing is not None:
                    return None      # 缺 2 段以上，FEC 救不回
                missing = i

        if missing is not None:
            group = missing // FEC_GROUP
            fec = p["fec"].get(group)
            if fec is None:
                return None
            g_start = group * FEC_GROUP
            g_end = min(g_start + FEC_GROUP, cnt)
            rec = bytearray(fec)
            for i in range(g_start, g_end):
                if i == missing:
                    continue
                s = segs.get(i)
                if s is None:
                    return None
                for k in range(len(s)):
                    rec[k] ^= s[k]
            if missing == cnt - 1:
                ln = p["total"] - missing * SEG_MAX
                if 0 < ln < len(rec):
                    rec = rec[:ln]
            segs[missing] = bytes(rec)
            p["used_fec"] = True

        out = bytearray()
        for i in range(cnt):
            s = segs.get(i)
            if s is None:
                return None
            out += s
        return bytes(out)

    # ---------- 统计 ----------
    def stats(self):
        now = time.time()
        with self.lock:
            jpg = self.latest_jpeg
            w, h = self.latest_w, self.latest_h
        recent = [(t, n) for (t, n) in self.frames if now - t <= 5.0]
        if recent:
            span = max(now - recent[0][0], 0.001)
            fps = len(recent) / span
            avg_kb = sum(n for _, n in recent) / len(recent) / 1024
            peak_kb = max(n for _, n in recent) / 1024
            # 码率按最近 5 秒的字节数算
            kbps = sum(n for _, n in recent) / span / 1024
        else:
            fps = avg_kb = peak_kb = kbps = 0
        return {
            "fps": round(fps, 1),
            "avg_kb": round(avg_kb, 1),
            "peak_kb": round(peak_kb, 1),
            "kbps": round(kbps),
            "pkt_count": self.pkt_count,
            "byte_count": self.byte_count,
            "complete_frames": self.complete_frames,
            "fec_recovered": self.fec_recovered,
            "frame_loss": self.frame_loss,
            "resolution": f"{w}x{h}" if w else "-",
            "has_frame": jpg is not None,
        }

    def history(self):
        """最近 60 秒每秒帧数，供画曲线。"""
        now = time.time()
        buckets = defaultdict(int)
        for t, _ in self.frames:
            buckets[int(now - t)] += 1
        return [buckets.get(i, 0) for i in range(59, -1, -1)]

    def close(self):
        self.running = False
        try:
            self.stop_stream()
            self.sock.close()
        except Exception:
            pass


RX = UdpReceiver(BOARD)


# ==================== 固件状态（HTTP /status）====================
def fetch_fw_status():
    try:
        url = f"http://{BOARD}/status"
        with urllib.request.urlopen(url, timeout=1.2) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"error": str(e)}


# ==================== 页面 ====================
PAGE = """<!DOCTYPE html><html><head><meta charset='utf-8'>
<title>护花使者 · 视觉板验收</title><style>
*{box-sizing:border-box}
body{font-family:system-ui;background:#0d0d0f;color:#e8e8e8;margin:0;padding:14px}
h2{margin:0 0 10px;font-size:18px;color:#7fe}
.grid{display:grid;grid-template-columns:1fr 300px;gap:14px;align-items:start}
@media(max-width:900px){.grid{grid-template-columns:1fr}}
img{width:100%;border-radius:8px;background:#1a1a1a;min-height:200px}
.card{background:#17171b;border:1px solid #26262c;border-radius:8px;padding:12px;margin-bottom:12px}
.card h3{margin:0 0 8px;font-size:13px;color:#888;font-weight:600;letter-spacing:.5px}
.row{display:flex;justify-content:space-between;padding:3px 0;font-size:14px;
font-family:ui-monospace,monospace}
.row span:first-child{color:#999}
.big{font-size:26px;font-weight:700;color:#7fe;font-family:ui-monospace,monospace}
.ok{color:#5d5}.bad{color:#f66}.warn{color:#fa3}
canvas{width:100%;height:80px;display:block}
.btns{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}
button{background:#2a2a34;color:#ddd;border:1px solid #3a3a46;border-radius:6px;
padding:8px 14px;font-size:14px;cursor:pointer}
button:hover{background:#34343f}
button.on{background:#2d5bd1;border-color:#2d5bd1;color:#fff}
</style></head><body>
<h2>护花使者 · 视觉板验收</h2>
<div class='btns'>
__PROFILE_BUTTONS__
<button onclick="cmd('VSTOP')">停止</button>
<button onclick="location.reload()">重连</button>
</div>
<div class='grid'>
<div>
<img id='v' src='/stream' alt='等待画面...'>
<div class='card'><h3>帧率（最近 60 秒）</h3><canvas id='c' width='600' height='80'></canvas></div>
</div>
<div>
<div class='card'>
<h3>UDP 链路实测（脚本侧统计）</h3>
<div class='big' id='fps'>-</div>
<div style='font-size:12px;color:#888;margin-bottom:8px'>fps</div>
<div class='row'><span>码率</span><b id='kbps'>-</b></div>
<div class='row'><span>均帧 / 峰值</span><b id='kb'>-</b></div>
<div class='row'><span>分辨率</span><b id='res'>-</b></div>
<div class='row'><span>完整帧</span><b id='cf'>-</b></div>
<div class='row'><span>FEC 救回</span><b id='fec' class='ok'>-</b></div>
<div class='row'><span>放弃帧</span><b id='lost'>-</b></div>
</div>
<div class='card'>
<h3>固件自报（/status）</h3>
<div class='row'><span>档位 / 帧率</span><b id='fres'>-</b></div>
<div class='row'><span>当前画质</span><b id='fq'>-</b></div>
<div class='row'><span>自适应降质</span><b id='fadown'>-</b></div>
<div class='row'><span>发送队列</span><b id='fq_d'>-</b></div>
<div class='row'><span>队列满丢帧</span><b id='fdrop'>-</b></div>
<div class='row'><span>PSRAM 剩余</span><b id='fps_ram'>-</b></div>
</div>
<div class='card'><h3>诊断</h3><div id='diag' style='font-size:13px;color:#999'>…</div></div>
</div>
</div>
<script>
let last = {};
async function cmd(c){await fetch('/cmd?c='+encodeURIComponent(c));}
function draw(hist){
  const cv=document.getElementById('c'),x=cv.getContext('2d');
  const w=cv.width,h=cv.height,mx=Math.max(15,...hist);
  x.clearRect(0,0,w,h);
  x.strokeStyle='#2b2b33';x.beginPath();
  for(let i=0;i<=3;i++){const y=h*i/3;x.moveTo(0,y);x.lineTo(w,y);}x.stroke();
  x.strokeStyle='#4d9fff';x.lineWidth=2;x.beginPath();
  hist.forEach((v,i)=>{const px=i/(hist.length-1)*w,py=h-(v/mx)*h;
    i?x.lineTo(px,py):x.moveTo(px,py);});
  x.stroke();
  x.fillStyle='#666';x.font='10px monospace';
  x.fillText('峰值 '+mx+' fps',4,11);
}
async function tick(){
  try{
    const s=await (await fetch('/stats',{cache:'no-store'})).json();
    const f=s.fw||{};
    document.getElementById('fps').textContent=s.fps;
    document.getElementById('kbps').textContent=s.kbps+' KB/s';
    document.getElementById('kb').textContent=s.avg_kb+' / '+s.peak_kb+' KB';
    document.getElementById('res').textContent=s.resolution;
    document.getElementById('cf').textContent=s.complete_frames;
    document.getElementById('fec').textContent=s.fec_recovered;
    document.getElementById('lost').textContent=s.frame_loss;
    document.getElementById('fres').textContent=(f.res||'-')+' / '+(f.fps||'-')+'fps';
    const q=f.q,qb=f.qbase;
    const qe=document.getElementById('fq');
    qe.textContent='q'+(q||'-');
    qe.className=(qb>0&&q>qb)?'warn':'';
    document.getElementById('fadown').textContent=f.adown||0;
    document.getElementById('fq_d').textContent=(f.queue||0)+'/2';
    document.getElementById('fdrop').textContent=f.dropped||0;
    document.getElementById('fps_ram').textContent=(f.psram_free_kb||'-')+' KB';

    // 诊断：把「固件发了多少」和「脚本收到多少」对上
    let d='';
    if(f.error) d='⚠ 无法读取 /status：'+(f.error);
    else if(!f.streaming) d='固件未推流（点上方档位按钮开始）';
    else if(s.fps<3) d='帧率过低：检查信号/距离，或降低分辨率';
    else if(s.frame_loss>s.complete_frames*0.15) d='丢帧偏多：链路不稳，建议降档';
    else if(q&&qb>0&&q>qb) d='自适应正在降质保帧率（画面变复杂时会这样）';
    else d='链路正常';
    document.getElementById('diag').textContent=d;

    draw(s.history||[]);
  }catch(e){
    document.getElementById('diag').textContent='统计读取失败：'+e;
  }
}
tick();setInterval(tick,1000);
</script>
</body></html>"""


PROFILE_HTML = "\n".join(
    f'<button onclick="cmd(\'VSTART {r} {f} {q}\')">{n} {f}fps</button>'
    for (n, r, f, q) in PROFILES
)
PAGE = PAGE.replace("__PROFILE_BUTTONS__", PROFILE_HTML)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, ctype, body):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def do_GET(self):
        if self.path == "/":
            self._send(200, "text/html; charset=utf-8", PAGE)

        elif self.path == "/stats":
            st = RX.stats()
            st["fw"] = fetch_fw_status()
            st["history"] = RX.history()
            self._send(200, "application/json", json.dumps(st))

        elif self.path.startswith("/cmd"):
            from urllib.parse import parse_qs, urlparse
            qs = parse_qs(urlparse(self.path).query)
            c = qs.get("c", [""])[0]
            ok = RX.send(c) if c else False
            self._send(200, "application/json", json.dumps({"ok": ok}))

        elif self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type",
                             "multipart/x-mixed-replace; boundary=frame")
            self.end_headers()
            try:
                while True:
                    with RX.lock:
                        jpg = RX.latest_jpeg
                    if jpg:
                        head = (b"--frame\r\nContent-Type: image/jpeg\r\n"
                                b"Content-Length: " + str(len(jpg)).encode() + b"\r\n\r\n")
                        self.wfile.write(head)
                        self.wfile.write(jpg)
                        self.wfile.write(b"\r\n")
                    time.sleep(1 / 25)
            except Exception:
                pass

        else:
            self._send(404, "text/plain", "404")


def main():
    print(f"视觉板: {BOARD}")
    info = RX.vinfo()
    if not info:
        print("❌ 板子无应答。请确认：")
        print("   1. 电脑已连 HuHuaShiZhe-CAM 热点（或与板子同网段）")
        print(f"   2. 能 ping 通 {BOARD}")
        print(f"   3. 板子已上电，串口日志无报错")
        sys.exit(1)

    print(f"✅ 板子在线: {info}")
    print("发送 VSTART（均衡 HD 15fps）…")
    RX.start_stream(3, 15, 10)
    time.sleep(1.0)

    srv = ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    print(f"\n👉 打开 http://127.0.0.1:{HTTP_PORT} 验收")
    print("   页面顶部按钮可切档位；Ctrl+C 退出\n")
    try:
        import webbrowser
        threading.Timer(1.0, lambda: webbrowser.open(
            f"http://127.0.0.1:{HTTP_PORT}")).start()
    except Exception:
        pass

    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n退出…")
    finally:
        RX.close()
        srv.shutdown()


if __name__ == "__main__":
    main()
