# -*- coding: utf-8 -*-
"""
训练工作线程：封装 Ultralytics 训练过程
- 后台线程执行训练，不冻结界面
- 每 2 秒轮询 results.csv，把最新指标发给界面实时绘图
- 训练结束/出错通过信号通知
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import time
import threading
import traceback

# 中文路径下 Python JSON 解码兜底
os.environ.setdefault("PYTHONUTF8", "1")

from PySide6.QtCore import QObject, Signal

# 检测任务 results.csv 的标准列（Ultralytics 8.x）
DETECT_COLUMNS = [
    "epoch", "train/box_loss", "train/cls_loss", "train/dfl_loss",
    "metrics/precision(B)", "metrics/recall(B)",
    "metrics/mAP50(B)", "metrics/mAP50-95(B)",
    "val/box_loss", "val/cls_loss", "val/dfl_loss",
    "lr/pg0", "lr/pg1", "lr/pg2",
]

# 分类任务 results.csv 的标准列
CLASSIFY_COLUMNS = [
    "epoch", "train/loss",
    "metrics/accuracy_top1", "metrics/accuracy_top5",
    "val/loss", "lr/pg0", "lr/pg1", "lr/pg2",
]


def _read_csv_rows(csv_path):
    """读取 results.csv，返回 (columns, rows[list[list[float|str]]])"""
    import csv
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        lines = [ln for ln in reader if ln]
    if not lines:
        return [], []
    header = [h.strip() for h in lines[0]]
    rows = []
    for ln in lines[1:]:
        vals = []
        for cell in ln:
            cell = cell.strip()
            try:
                vals.append(float(cell))
            except ValueError:
                vals.append(cell)
        rows.append(vals)
    return header, rows


class _WorkerBase(QObject):
    """线程基类：用普通 Python 线程代替 QThread。
    实测 QThread 内跑 PyTorch/ultralytics 会随机触发 0xC0000409 原生崩溃
    （主线程与纯 threading.Thread 均稳定，仅 QThread 必崩），
    而 Python 线程发出的 Signal 会自动按队列连接投递回主线程，行为不变。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self.run, daemon=True)
        self._thread.start()

    def isRunning(self):
        t = self._thread
        return bool(t and t.is_alive())

    def wait(self, timeout=None):
        if self._thread:
            self._thread.join(timeout)


class TrainWorker(_WorkerBase):
    """后台训练线程"""
    log_line = Signal(str)          # 一行训练日志
    metrics = Signal(dict)          # 最新一批指标（每个 epoch 一条）
    finished_ok = Signal(str)       # 训练完成，参数为 best.pt 路径
    failed = Signal(str)            # 训练失败，参数为错误信息
    stopped = Signal()              # 用户停止并已清理半成品数据

    def __init__(self, task, model_size, data_root, project_dir, name,
                 epochs, imgsz, batch, device, parent=None):
        super().__init__(parent)
        self.task = task                # 'detect' | 'classify'
        self.model_size = model_size    # 'n' | 's' | 'm'
        self.data_root = data_root      # 数据集根目录
        self.project_dir = project_dir  # 输出根目录 runs
        self.name = name                # 本次训练名称
        self.epochs = epochs
        self.imgsz = imgsz
        self.batch = batch
        self.device = device            # 'cpu' | '0' | ''
        self._stop_flag = False
        self._proc = None               # 训练子进程（train_runner.py）
        self._cfg_path = None
        self.best_pt = None
        self._sent_rows = 0

    def stop(self):
        """请求停止：立即终止训练子进程树（taskkill /T），并清除半成品输出目录。"""
        self._stop_flag = True
        p = self._proc
        if p is not None and p.poll() is None:
            subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"],
                           capture_output=True)

    def _cleanup_run(self):
        """删除本次训练的输出目录（含半成品权重、曲线、日志）"""
        run_dir = os.path.join(os.path.abspath(self.project_dir), self.name)
        shutil.rmtree(run_dir, ignore_errors=True)
        self.best_pt = None

    # ---------- 主流程 ----------
    def run(self):
        try:
            import json as _json
            import subprocess

            self.log_line.emit("正在启动训练子进程...")
            cfg = dict(
                task=self.task,
                model_size=self.model_size,
                data_root=os.path.abspath(self.data_root),
                epochs=int(self.epochs),
                imgsz=int(self.imgsz),
                batch=int(self.batch),
                device=self.device,
                name=self.name,
                project_dir=os.path.abspath(self.project_dir),
            )
            self._cfg_path = os.path.join(os.path.abspath(self.project_dir), f"{self.name}_cfg.json")
            os.makedirs(os.path.abspath(self.project_dir), exist_ok=True)
            with open(self._cfg_path, "w", encoding="utf-8") as f:
                _json.dump(cfg, f, ensure_ascii=False)

            runner = os.path.join(os.path.dirname(os.path.abspath(__file__)), "train_runner.py")
            env = os.environ.copy()
            env["PYTHONUTF8"] = "1"
            env["PYTHONIOENCODING"] = "utf-8"
            self._proc = subprocess.Popen(
                [sys.executable, runner, self._cfg_path],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
                env=env, cwd=os.path.dirname(runner),
            )

            # 日志转发线程：子进程 stdout → 界面日志框 + 控制台（bat 窗口）
            def _read_out():
                for line in self._proc.stdout:
                    ln = line.rstrip()
                    if not ln:
                        continue
                    if ln.startswith("BEST_PT "):
                        self.best_pt = ln[8:].strip()
                    try:
                        print(ln, flush=True)
                    except OSError:
                        pass
                    self.log_line.emit(ln)

            t_out = threading.Thread(target=_read_out, daemon=True)
            t_out.start()

            # 指标轮询：results.csv 新增行 → 界面曲线
            def _poll_metrics():
                run_dir = os.path.join(os.path.abspath(self.project_dir), self.name)
                csv_path = os.path.join(run_dir, "results.csv")
                while not self._stop_flag and self.isRunning():
                    try:
                        if os.path.isfile(csv_path):
                            header, rows = _read_csv_rows(csv_path)
                            for row in rows[self._sent_rows:]:
                                self._sent_rows += 1
                                self.metrics.emit(dict(zip(header, row)))
                    except Exception as e:
                        self.log_line.emit(f"[指标轮询] {e}")
                    time.sleep(2)

            t_metrics = threading.Thread(target=_poll_metrics, daemon=True)
            t_metrics.start()

            code = self._proc.wait()
            self._proc = None
            try:
                if self._cfg_path and os.path.isfile(self._cfg_path):
                    os.remove(self._cfg_path)
            except OSError:
                pass

            if self._stop_flag:
                self._cleanup_run()
                self.log_line.emit("=== 训练已停止，半成品数据已清除 ===")
                self.stopped.emit()
                return
            if code == 0:
                run_dir = os.path.join(os.path.abspath(self.project_dir), self.name)
                fallback = os.path.join(run_dir, "weights", "best.pt")
                if not (self.best_pt and os.path.isfile(self.best_pt)) and os.path.isfile(fallback):
                    self.best_pt = fallback
                if self.best_pt and os.path.isfile(self.best_pt):
                    self.log_line.emit(f"训练完成，最优权重：{self.best_pt}")
                    self.finished_ok.emit(self.best_pt)
                else:
                    self.failed.emit("训练进程正常退出，但未找到 best.pt 权重文件")
            else:
                self.failed.emit(f"训练进程异常退出（退出码 {code}），详见上方日志")
        except Exception:
            self.log_line.emit("训练出错，详见错误信息")
            self.failed.emit(traceback.format_exc())


class InferWorker(_WorkerBase):
    """试跑线程：对单张图片或整个文件夹做推理（自动适配检测/分类模型）"""
    log_line = Signal(str)
    one_result = Signal(str, str)   # (图片路径, 结果描述)
    finished_ok = Signal(str)       # 输出目录
    failed = Signal(str)

    def __init__(self, weights, source, save_dir, conf, parent=None):
        super().__init__(parent)
        self.weights = weights
        self.source = source
        self.save_dir = save_dir
        self.conf = conf

    def run(self):
        try:
            from ultralytics import YOLO
            self.log_line.emit(f"加载权重：{self.weights}")
            model = YOLO(self.weights)
            self.log_line.emit(f"推理中：{self.source}（conf={self.conf:.2f}）")
            results = model.predict(
                source=self.source,
                conf=float(self.conf),
                save=True,
                project=os.path.abspath(self.save_dir),
                name="predict",
                exist_ok=True,
                line_width=3,
                workers=0,  # Qt 线程内禁用多进程 dataloader，避免 Windows spawn 崩溃
            )
            out_dir = os.path.join(os.path.abspath(self.save_dir), "predict")
            for r in results:
                img_path = getattr(r, "path", "")
                probs = getattr(r, "probs", None)
                if probs is not None:
                    # 分类模型：整图类别 + 置信度
                    top1 = r.names[int(probs.top1)]
                    label = f"{top1}  {float(probs.top1conf) * 100:.1f}%"
                else:
                    # 检测模型：目标框数量
                    boxes = getattr(r, "boxes", None)
                    n = 0 if boxes is None else len(boxes)
                    label = f"检出 {n} 个目标"
                self.one_result.emit(img_path, label)
            self.finished_ok.emit(out_dir)
        except Exception:
            self.failed.emit(traceback.format_exc())


# onnx2tf 控制台里的 ANSI 颜色码
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


class ExportWorker(_WorkerBase):
    """导出线程：把 best.pt 导出为手机可用格式

    TFLite 注意：ultralytics 8.4 起 TFLite/LiteRT 直连导出只支持 Linux x86 与 macOS，
    Windows 上调用 model.export(format='tflite') 会抛
    AssertionError: LiteRT export only supported on Linux x86 and macOS。
    因此 Windows 改为两步：ONNX(opset 13) → onnx2tf → float32 TFLite。
    """
    log_line = Signal(str)
    finished_ok = Signal(str)   # 导出文件路径
    failed = Signal(str)

    def __init__(self, weights, fmt, parent=None):
        super().__init__(parent)
        self.weights = weights
        self.fmt = fmt  # 'tflite' | 'onnx'

    def run(self):
        try:
            from ultralytics import YOLO
            model = YOLO(self.weights)
            out_dir = os.path.dirname(os.path.abspath(self.weights))

            if self.fmt == 'onnx':
                self.log_line.emit("开始导出 ONNX（opset 13）...")
                path = model.export(format='onnx', opset=13)
                self.log_line.emit(f"导出完成：{path}")
                self.finished_ok.emit(str(path))
                return

            self.log_line.emit("步骤 1/2：导出 ONNX（opset 13）...")
            onnx_path = str(model.export(format='onnx', opset=13))
            self.log_line.emit(f"ONNX 已生成：{onnx_path}")

            self.log_line.emit("步骤 2/2：onnx2tf 转换为 TFLite（float32，首次较慢）...")
            tflite_path = self._convert_to_tflite(onnx_path, out_dir)

            self._write_labels(model, tflite_path)
            self._check_tflite(tflite_path, len(model.names))

            self.log_line.emit(f"导出完成：{tflite_path}")
            self.finished_ok.emit(tflite_path)
        except Exception:
            self.failed.emit(traceback.format_exc())

    def _convert_to_tflite(self, onnx_path, out_dir):
        """调用 onnx2tf 把 ONNX 转成 float32 TFLite，返回生成的 .tflite 路径"""
        tf_dir = os.path.join(out_dir, "tflite")
        os.makedirs(tf_dir, exist_ok=True)

        cmd = [sys.executable, "-m", "onnx2tf", "-i", onnx_path, "-o", tf_dir]
        env = dict(os.environ)
        env["TF_CPP_MIN_LOG_LEVEL"] = "2"
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
        )
        last = ""
        for raw in proc.stdout:
            line = _ANSI_RE.sub("", raw).rstrip()
            # 过滤 tqdm 进度条造成的刷屏（含 it/s 的刷新行）
            if not line or "it/s" in line or "s/it" in line or line == last:
                continue
            last = line
            self.log_line.emit(line)
        proc.wait()
        if proc.returncode != 0:
            raise RuntimeError(
                f"onnx2tf 转换失败（退出码 {proc.returncode}）。"
                "请确认已 pip install onnx2tf tensorflow"
            )

        files = glob.glob(os.path.join(tf_dir, "**", "*.tflite"), recursive=True)
        if not files:
            raise RuntimeError(f"未在 {tf_dir} 找到生成的 .tflite 文件")
        # 优先 float32（CPU 解释器对 float16 会 ALLOC_FAIL）
        float32 = [f for f in files if "float32" in os.path.basename(f).lower()]
        return max(float32 or files, key=os.path.getsize)

    def _write_labels(self, model, tflite_path):
        """把类别名按输出索引顺序写到 *_labels.txt，便于接入 App 模型注册表"""
        names = model.names
        if isinstance(names, dict):
            pairs = sorted(names.items())
        else:
            pairs = list(enumerate(names))
        lines = [str(v) for _, v in pairs]
        label_path = os.path.splitext(tflite_path)[0] + "_labels.txt"
        with open(label_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        self.log_line.emit(
            f"类别标签已写入：{label_path}（共 {len(lines)} 类，行号顺序即模型输出索引）"
        )

    def _check_tflite(self, tflite_path, num_classes):
        """子进程校验 TFLite 输入输出形状，避免污染 GUI 进程内存"""
        code = (
            "import sys, os\n"
            "os.environ['TF_CPP_MIN_LOG_LEVEL']='3'\n"
            "import tensorflow as tf\n"
            # 用 model_content 读取，绕过 TF Lite C++ 层对中文路径打不开的问题
            "data = open(sys.argv[1], 'rb').read()\n"
            "i = tf.lite.Interpreter(model_content=data)\n"
            "i.allocate_tensors()\n"
            "a = i.get_input_details()[0]; b = i.get_output_details()[0]\n"
            "print('IN ', a['shape'].tolist(), a['dtype'].__name__)\n"
            "print('OUT', b['shape'].tolist(), b['dtype'].__name__)\n"
        )
        try:
            r = subprocess.run(
                [sys.executable, "-c", code, tflite_path],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=180,
            )
            if r.returncode != 0:
                self.log_line.emit(f"（形状校验跳过：{(r.stderr or '').strip()[-200:]}）")
                return
            for line in (r.stdout or "").splitlines():
                if line.strip():
                    self.log_line.emit("校验 " + line.strip())
            size_mb = os.path.getsize(tflite_path) / 1024 / 1024
            self.log_line.emit(f"文件大小 {size_mb:.1f} MB，类别数 {num_classes}")

            # 从输出里取出输入边长，提示 App 注册表要填的 inputSize
            m = re.search(r"IN\s+\[1,\s*(\d+),\s*(\d+),\s*3\]", r.stdout or "")
            if m:
                side = m.group(1)
                self.log_line.emit(
                    f"接入 App 时，model_catalog.dart 中该模型的 inputSize 必须填 {side}"
                )
            if f"[1, {num_classes}]" not in (r.stdout or ""):
                self.log_line.emit("提示：输出形状与类别数不一致，请在 App 端实测确认")
        except Exception as e:
            self.log_line.emit(f"（形状校验跳过：{e}）")
