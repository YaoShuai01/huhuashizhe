# -*- coding: utf-8 -*-
"""
训练工作线程：封装 Ultralytics 训练过程
- 后台线程执行训练，不冻结界面
- 每 2 秒轮询 results.csv，把最新指标发给界面实时绘图
- 训练结束/出错通过信号通知
"""
import os
import sys
import time
import traceback

# 中文路径下 Python JSON 解码兜底
os.environ.setdefault("PYTHONUTF8", "1")

from PySide6.QtCore import QThread, Signal

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


def _resolve_model_path(model_size):
    """优先使用工具目录内自带的预训练权重（避免运行时从 GitHub 下载被 403 限流），
    找不到本地权重时回退为裸名称，由 ultralytics 自行下载。"""
    base = os.path.dirname(os.path.abspath(__file__))
    for cand in (
        os.path.join(base, f"yolo11{model_size}.pt"),
        os.path.join(base, "weights", f"yolo11{model_size}.pt"),
    ):
        if os.path.isfile(cand):
            return cand
    return f"yolo11{model_size}.pt"


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


class TrainWorker(QThread):
    """后台训练线程"""
    log_line = Signal(str)          # 一行训练日志
    metrics = Signal(dict)          # 最新一批指标（每个 epoch 一条）
    finished_ok = Signal(str)       # 训练完成，参数为 best.pt 路径
    failed = Signal(str)            # 训练失败，参数为错误信息

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
        self.best_pt = None
        self._sent_rows = 0

    def stop(self):
        """请求停止（训练循环内配合 ultralytics 回调中断比较复杂，
        这里直接杀死进程由外部 bat 控制，故仅提示）"""
        self._stop_flag = True

    # ---------- 数据集准备 ----------
    def _prepare_detection_data(self):
        """检测数据集：约定根目录下 train/images、train/labels、val/images、val/labels，
        类别名从根目录 classes.txt 读取（每行一个）。生成 data.yaml。"""
        import yaml  # ultralytics 依赖里带 pyyaml

        root = os.path.abspath(self.data_root)
        tr_img = os.path.join(root, "train", "images")
        tr_lbl = os.path.join(root, "train", "labels")
        va_img = os.path.join(root, "val", "images")
        va_lbl = os.path.join(root, "val", "labels")
        for d in (tr_img, va_img):
            if not os.path.isdir(d):
                raise FileNotFoundError(
                    f"检测数据集目录不完整：缺少 {d}\n"
                    f"请按  根目录/train/images、根目录/train/labels、"
                    f"根目录/val/images、根目录/val/labels 组织"
                )
        cls_file = os.path.join(root, "classes.txt")
        names = {}
        if os.path.isfile(cls_file):
            with open(cls_file, "r", encoding="utf-8") as f:
                names = {i: ln.strip() for i, ln in enumerate(f) if ln.strip()}
        else:
            # 未提供 classes.txt 时，从标签文件扫描最大类别 id
            max_id = -1
            for d in (tr_lbl, va_lbl):
                if not os.path.isdir(d):
                    continue
                for fn in os.listdir(d):
                    if not fn.lower().endswith(".txt"):
                        continue
                    with open(os.path.join(d, fn), "r", encoding="utf-8") as f:
                        for line in f:
                            parts = line.split()
                            if parts:
                                try:
                                    max_id = max(max_id, int(parts[0]))
                                except ValueError:
                                    pass
            names = {i: f"class_{i}" for i in range(max_id + 1)} if max_id >= 0 else {0: "object"}
        yaml_path = os.path.join(root, "data.yaml")
        with open(yaml_path, "w", encoding="utf-8") as f:
            yaml.safe_dump({
                "path": root,
                "train": os.path.join("train", "images"),
                "val": os.path.join("val", "images"),
                "names": names,
            }, f, allow_unicode=True)
        return yaml_path, len(names)

    def _prepare_classify_data(self):
        """分类数据集：约定根目录下 train/<类别名>/*.图片、val/<类别名>/*.图片"""
        root = os.path.abspath(self.data_root)
        for sub in ("train", "val"):
            d = os.path.join(root, sub)
            if not os.path.isdir(d) or not any(
                os.path.isdir(os.path.join(d, c)) for c in os.listdir(d)
            ):
                raise FileNotFoundError(
                    f"分类数据集目录不完整：缺少 {d}\\<类别名>\\图片\n"
                    f"请按  根目录/train/类别A/xx.jpg、根目录/val/类别A/xx.jpg 组织"
                )
        return root, 0

    # ---------- 主流程 ----------
    def run(self):
        try:
            self.log_line.emit("正在初始化训练环境（首次运行会自动下载预训练权重）...")
            from ultralytics import YOLO

            if self.task == "detect":
                data, ncls = self._prepare_detection_data()
                self.log_line.emit(f"检测数据集就绪：{ncls} 个类别")
            else:
                data, _ = self._prepare_classify_data()
                self.log_line.emit("分类数据集就绪")

            model_name = _resolve_model_path(self.model_size)
            self.log_line.emit(f"加载基础模型：{model_name}")
            model = YOLO(model_name)

            args = dict(
                data=data,
                epochs=int(self.epochs),
                imgsz=int(self.imgsz),
                batch=int(self.batch) if int(self.batch) > 0 else -1,  # -1 自动批大小
                project=os.path.abspath(self.project_dir),
                name=self.name,
                exist_ok=True,
                device=None if self.device in ("", "auto") else self.device,
                workers=2,           # Windows 下多进程 dataloader 易卡死，保守取 2
                plots=True,
                patience=50,
            )
            self.log_line.emit(f"开始训练：epochs={args['epochs']}, imgsz={args['imgsz']}, batch={args['batch']}")

            import threading

            def _poll_metrics():
                """轮询 results.csv，把新增行发给界面"""
                run_dir = os.path.join(os.path.abspath(self.project_dir), self.name)
                csv_path = os.path.join(run_dir, "results.csv")
                while not self._stop_flag and self.isRunning():
                    try:
                        if os.path.isfile(csv_path):
                            header, rows = _read_csv_rows(csv_path)
                            for row in rows[self._sent_rows:]:
                                self._sent_rows += 1
                                m = dict(zip(header, row))
                                self.metrics.emit(m)
                    except Exception as e:  # 轮询失败不影响训练
                        self.log_line.emit(f"[指标轮询] {e}")
                    time.sleep(2)

            t = threading.Thread(target=_poll_metrics, daemon=True)
            t.start()

            results = model.train(**args)

            # best 权重路径
            run_dir = os.path.join(os.path.abspath(self.project_dir), self.name)
            self.best_pt = os.path.join(run_dir, "weights", "best.pt")
            if not os.path.isfile(self.best_pt):
                self.best_pt = str(getattr(model, "trainer", None) and model.trainer.best or self.best_pt)
            self.log_line.emit(f"训练完成，最优权重：{self.best_pt}")
            self.finished_ok.emit(self.best_pt)

        except Exception:
            err = traceback.format_exc()
            self.log_line.emit("训练出错，详见错误信息")
            self.failed.emit(err)


class InferWorker(QThread):
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


class ExportWorker(QThread):
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
