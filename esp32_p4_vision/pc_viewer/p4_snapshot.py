# -*- coding: utf-8 -*-
"""
读取 ESP32-P4 原生 USB 口发来的 HV 帧，保存为 JPEG 并打开。

固件侧协议：'H''V' + type(1) + len32(LE) + JPEG 数据
用法：python p4_snapshot.py [COM7]
"""
import os
import sys
import time

import serial

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p4_snapshot.jpg")
PORT_DEFAULT = "COM8"
BAUD = 921600


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else PORT_DEFAULT
    print("打开 %s @ %d，等待 JPEG ..." % (port, BAUD))

    ser = serial.Serial(port, BAUD, timeout=0.2)
    try:
        ser.dtr = False
        ser.rts = False
    except Exception:
        pass
    buf = bytearray()
    deadline = time.time() + 60

    while time.time() < deadline:
        buf += ser.read(8192)
        idx = buf.find(b"HV")
        if idx < 0:
            if len(buf) > 1:
                del buf[:-1]
            continue
        if len(buf) - idx < 8:
            del buf[:idx]
            continue

        length = int.from_bytes(buf[idx + 3:idx + 7], "little")
        if length <= 0 or length >= 5_000_000:
            del buf[idx:idx + 1]
            continue
        if len(buf) - idx < 8 + length:
            del buf[:idx]
            continue

        jpg = bytes(buf[idx + 8:idx + 8 + length])
        with open(OUT, "wb") as f:
            f.write(jpg)
        print("已保存 %s（%d 字节）" % (OUT, len(jpg)))
        try:
            os.startfile(OUT)
        except OSError:
            pass
        return 0

    print("超时：没有收到完整 JPEG")
    return 2


if __name__ == "__main__":
    sys.exit(main())
