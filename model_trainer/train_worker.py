# -*- coding: utf-8 -*-
"""
训练工作线程：封装 Ultralytics 训练过程
- 后台线程执行训练，不冻结界面
- 每 2 秒轮询 results.csv，把最新指标发给界面实时绘图
- 训练结束/出错通过信号通知
"""
import os
import shutil
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

            # 日志转发线程：子进程 stdout → 界面日志框
            def _read_out():
                for line in self._proc.stdout:
                    ln = line.rstrip()
                    if not ln:
                        continue
                    if ln.startswith("BEST_PT "):
                        self.best_pt = ln[8:].strip()
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
    """试跑线程：对单张图片或整个文件夹做推理"""
    log_line = Signal(str)
    one_result = Signal(str, int)   # (图片路径, 检出目标数 或 -1)
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
                boxes = getattr(r, "boxes", None)
                n = 0 if boxes is None else len(boxes)
                self.one_result.emit(img_path, n)
            self.finished_ok.emit(out_dir)
        except Exception:
            self.failed.emit(traceback.format_exc())


class ExportWorker(_WorkerBase):
    """导出线程：把 best.pt 导出为 tflite int8 / onnx"""
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
            self.log_line.emit(f"开始导出 {self.fmt.upper()}（int8 量化，首次需几分钟）...")
            model = YOLO(self.weights)
            path = model.export(format=self.fmt, int8=True, data=None)
            self.log_line.emit(f"导出完成：{path}")
            self.finished_ok.emit(str(path))
        except Exception:
            self.failed.emit(traceback.format_exc())
