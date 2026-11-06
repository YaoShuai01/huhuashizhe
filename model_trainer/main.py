# -*- coding: utf-8 -*-
"""
护花使者 · 虫害识别模型训练器
PySide6 深色界面 + Ultralytics YOLO 训练引擎
功能页：训练配置 / 实时监控 / 模型试跑 / 导出部署
"""
import os
import sys
import time
import random

os.environ.setdefault("PYTHONUTF8", "1")

import matplotlib
matplotlib.rcParams["font.family"] = ["Microsoft YaHei UI", "SimHei", "sans-serif"]
matplotlib.rcParams["axes.unicode_minus"] = False

from PySide6.QtCore import Qt, QTimer, QSize
from PySide6.QtGui import QFont, QImage, QPixmap, QColor, QIcon
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QTabWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QFormLayout, QLabel, QPushButton, QLineEdit, QComboBox,
    QSpinBox, QFileDialog, QProgressBar, QPlainTextEdit, QGroupBox,
    QRadioButton, QMessageBox, QScrollArea, QSplitter, QListWidget,
    QListWidgetItem, QFrame,
)
from matplotlib.figure import Figure
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg

from train_worker import TrainWorker, InferWorker, ExportWorker

APP_VERSION = "v1.0.0"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RUNS_DIR = os.path.join(BASE_DIR, "runs")

# ---------------- 深色主题 ----------------
QSS = """
QWidget { background:#16181d; color:#e6e8ee; font-family:'Microsoft YaHei UI'; font-size:13px; }
QMainWindow, QTabWidget::pane { background:#16181d; border:none; }
QTabBar::tab {
    background:#1e2128; color:#9aa1ad; padding:10px 26px; margin-right:4px;
    border-top-left-radius:8px; border-top-right-radius:8px; font-size:14px;
}
QTabBar::tab:selected { background:#262b35; color:#ffffff; font-weight:bold; }
QTabBar::tab:hover { color:#d7dbe2; }
QGroupBox {
    background:#1e2128; border:1px solid #2c313c; border-radius:10px;
    margin-top:14px; padding:14px 12px 12px 12px; font-weight:bold; color:#e6e8ee;
}
QGroupBox::title { subcontrol-origin: margin; left:14px; padding:0 6px; color:#7fb2ff; }
QLineEdit, QComboBox, QSpinBox {
    background:#12141a; border:1px solid #2c313c; border-radius:6px;
    padding:6px 10px; color:#e6e8ee; selection-background-color:#2f6fdb;
}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus { border:1px solid #3d8bff; }
QComboBox::drop-down { border:none; width:26px; }
QComboBox QAbstractItemView {
    background:#1e2128; border:1px solid #2c313c; selection-background-color:#2f6fdb;
}
QPushButton {
    background:#2f6fdb; color:white; border:none; border-radius:8px;
    padding:9px 20px; font-weight:bold; font-size:13px;
}
QPushButton:hover { background:#3d7ce8; }
QPushButton:pressed { background:#2559b8; }
QPushButton:disabled { background:#333a46; color:#6a7280; }
QPushButton#danger { background:#d9484f; }
QPushButton#danger:hover { background:#e35d64; }
QPushButton#ghost { background:#262b35; color:#c8cdd6; }
QPushButton#ghost:hover { background:#313847; }
QProgressBar {
    background:#12141a; border:1px solid #2c313c; border-radius:7px;
    text-align:center; height:18px; color:#ffffff; font-weight:bold;
}
QProgressBar::chunk { background:qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #2f6fdb, stop:1 #7fb2ff); border-radius:6px; }
QPlainTextEdit {
    background:#101218; border:1px solid #2c313c; border-radius:8px;
    color:#b9e0a5; font-family:Consolas,'Courier New'; font-size:12px;
}
QListWidget { background:#12141a; border:1px solid #2c313c; border-radius:8px; }
QListWidget::item { padding:8px; border-bottom:1px solid #232833; }
QListWidget::item:selected { background:#2f6fdb; color:white; }
QLabel#title { font-size:19px; font-weight:bold; color:#ffffff; }
QLabel#sub { color:#8b93a1; font-size:12px; }
QLabel#hint { color:#8b93a1; font-size:12px; }
QLabel#stat { font-size:15px; font-weight:bold; color:#ffd479; }
QSplitter::handle { background:#2c313c; width:2px; }
QScrollBar:vertical { background:#16181d; width:10px; margin:0; }
QScrollBar::handle:vertical { background:#333a46; border-radius:5px; min-height:30px; }
QScrollBar::add-line, QScrollBar::sub-line { height:0; }
"""


class MetricCanvas(FigureCanvasQTAgg):
    """单张指标图"""

    def __init__(self, title, ylabel, color="#3d8bff", parent=None):
        self.fig = Figure(figsize=(3.4, 2.3), dpi=96, facecolor="#1e2128")
        super().__init__(self.fig)
        self.setParent(parent)
        self.ax = self.fig.add_subplot(111)
        self.color = color
        self.title = title
        self.ylabel = ylabel
        self._style()
        self.x, self.y, self.y2 = [], [], []

    def _style(self):
        ax = self.ax
        ax.set_facecolor("#16181d")
        ax.set_title(self.title, color="#e6e8ee", fontsize=10, fontweight="bold")
        ax.set_ylabel(self.ylabel, color="#9aa1ad", fontsize=8)
        ax.tick_params(colors="#9aa1ad", labelsize=7)
        for s in ax.spines.values():
            s.set_color("#2c313c")
        ax.grid(True, color="#232833", linewidth=0.6)
        self.fig.tight_layout()

    def update_data(self, x, y, y2=None):
        self.x, self.y = list(x), list(y)
        self.y2 = list(y2) if y2 else None
        self.ax.clear()
        self._style()
        self.ax.plot(self.x, self.y, color=self.color, linewidth=1.8,
                     marker="o", markersize=2.5, label=self.ylabel)
        if self.y2:
            self.ax.plot(self.x, self.y2, color="#ff9f43", linewidth=1.4,
                         linestyle="--", label="验证集")
        self.ax.legend(loc="lower right", fontsize=7, facecolor="#1e2128",
                       edgecolor="#2c313c", labelcolor="#c8cdd6")
        self.draw()


class TrainConfigPage(QWidget):
    """第一页：训练配置"""

    def __init__(self, on_start, parent=None):
        super().__init__(parent)
        self.on_start = on_start
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 18, 24, 18)
        lay.setSpacing(14)

        head = QLabel("训练配置")
        head.setObjectName("title")
        sub = QLabel("选择任务类型与模型规格，指定数据集后即可开始训练")
        sub.setObjectName("sub")
        lay.addWidget(head)
        lay.addWidget(sub)

        # 任务与模型
        g1 = QGroupBox("① 任务与模型")
        f1 = QGridLayout(g1)
        f1.setVerticalSpacing(10)

        f1.addWidget(QLabel("任务类型"), 0, 0)
        self.task = QComboBox()
        self.task.addItems(["目标检测（画框识别害虫/病斑位置）", "图像分类（判断整图健康/虫害）"])
        self.task.setMinimumWidth(340)
        f1.addWidget(self.task, 0, 1, 1, 3)

        f1.addWidget(QLabel("模型规格"), 1, 0)
        self.size = QComboBox()
        for label, tip in [
            ("n · 纳米（最快，适合手机端实时，精度较低）", "n"),
            ("s · 小型（推荐：精度与速度均衡）", "s"),
            ("m · 中型（精度更高，手机端会慢）", "m"),
        ]:
            self.size.addItem(label, tip)
        self.size.setCurrentIndex(1)
        f1.addWidget(self.size, 1, 1, 1, 3)

        self.size_hint = QLabel("")
        self.size_hint.setObjectName("hint")
        f1.addWidget(self.size_hint, 2, 1, 1, 3)
        f1.setColumnStretch(3, 1)
        lay.addWidget(g1)

        # 数据集
        g2 = QGroupBox("② 数据集")
        f2 = QGridLayout(g2)
        f2.setVerticalSpacing(10)
        f2.addWidget(QLabel("数据集根目录"), 0, 0)
        self.data_path = QLineEdit()
        self.data_path.setPlaceholderText("选择包含 train/ 与 val/ 子目录的数据集根目录")
        f2.addWidget(self.data_path, 0, 1)
        b_browse = QPushButton("浏览...")
        b_browse.setObjectName("ghost")
        b_browse.clicked.connect(self._browse_data)
        f2.addWidget(b_browse, 0, 2)
        hint = QLabel(
            "检测任务目录结构：根目录/train/images、train/labels、val/images、val/labels"
            "（类别名可选放在根目录 classes.txt，每行一个）；\n"
            "分类任务目录结构：根目录/train/类别名/*.jpg、val/类别名/*.jpg"
        )
        hint.setObjectName("hint")
        hint.setWordWrap(True)
        f2.addWidget(hint, 1, 0, 1, 3)
        lay.addWidget(g2)

        # 超参数
        g3 = QGroupBox("③ 训练参数（不懂可直接保持默认）")
        f3 = QGridLayout(g3)
        f3.setVerticalSpacing(10)
        f3.addWidget(QLabel("训练轮数 epochs"), 0, 0)
        self.epochs = QSpinBox(); self.epochs.setRange(1, 1000); self.epochs.setValue(100)
        f3.addWidget(self.epochs, 0, 1)
        f3.addWidget(QLabel("图像尺寸 imgsz"), 0, 2)
        self.imgsz = QComboBox()
        for s in (224, 320, 416, 640):
            self.imgsz.addItem(str(s), s)
        self.imgsz.setCurrentIndex(1)
        f3.addWidget(self.imgsz, 0, 3)
        f3.addWidget(QLabel("批大小 batch（-1 自动）"), 1, 0)
        self.batch = QSpinBox(); self.batch.setRange(-1, 128); self.batch.setValue(-1)
        f3.addWidget(self.batch, 1, 1)
        f3.addWidget(QLabel("计算设备"), 1, 2)
        self.device = QComboBox()
        self.device.addItem("自动（有显卡用显卡）", "auto")
        self.device.addItem("CPU（慢）", "cpu")
        self.device.addItem("GPU 0", "0")
        f3.addWidget(self.device, 1, 3)
        f3.addWidget(QLabel("本次训练名称"), 2, 0)
        self.run_name = QLineEdit()
        self.run_name.setText(time.strftime("run_%Y%m%d_%H%M%S"))
        f3.addWidget(self.run_name, 2, 1)
        lay.addWidget(g3)

        lay.addStretch(1)

        # 开始按钮
        row = QHBoxLayout()
        self.btn_start = QPushButton("▶  开始训练")
        self.btn_start.setMinimumHeight(44)
        self.btn_start.clicked.connect(self._emit_start)
        row.addStretch(1)
        row.addWidget(self.btn_start)
        row.addStretch(1)
        lay.addLayout(row)

        self.size.currentIndexChanged.connect(self._size_changed)
        self._size_changed()

    def _size_changed(self):
        tips = {
            "n": "约 6MB · 手机端可实时，建议数据量 ≥500 张/类",
            "s": "约 20MB · 推荐档位，建议数据量 ≥800 张/类",
            "m": "约 50MB · 精度优先，建议有 NVIDIA 显卡",
        }
        self.size_hint.setText(tips[self.size.currentData()])

    def _browse_data(self):
        d = QFileDialog.getExistingDirectory(self, "选择数据集根目录")
        if d:
            self.data_path.setText(d)

    def _emit_start(self):
        cfg = dict(
            task="detect" if self.task.currentIndex() == 0 else "classify",
            size=self.size.currentData(),
            data=self.data_path.text().strip(),
            epochs=self.epochs.value(),
            imgsz=self.imgsz.currentData(),
            batch=self.batch.value(),
            device=self.device.currentData(),
            name=self.run_name.text().strip() or time.strftime("run_%Y%m%d_%H%M%S"),
        )
        if not cfg["data"] or not os.path.isdir(cfg["data"]):
            QMessageBox.warning(self, "缺少数据集", "请先选择有效的数据集根目录")
            return
        # 任务类型自动识别：按数据集结构纠正（images+labels=检测，类别文件夹=分类），
        # 避免任务类型选错导致 FileNotFoundError
        tr = os.path.join(cfg["data"], "train")
        if os.path.isdir(tr):
            subdirs = [d for d in os.listdir(tr) if os.path.isdir(os.path.join(tr, d))]
            has_detect = os.path.isdir(os.path.join(tr, "images"))
            has_classify = any(d.lower() not in ("images", "labels") for d in subdirs)
            auto = "detect" if has_detect else ("classify" if has_classify else None)
            if auto and auto != cfg["task"]:
                idx = 0 if auto == "detect" else 1
                self.task.setCurrentIndex(idx)
                cfg["task"] = auto
                QMessageBox.information(
                    self, "已自动纠正任务类型",
                    f"检测到该数据集是{'目标检测' if auto == 'detect' else '图像分类'}结构，"
                    f"任务类型已自动切换，直接点开始训练即可。"
                )
        self.on_start(cfg)


class TrainMonitorPage(QWidget):
    """第二页：实时监控"""
    def __init__(self, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 18, 24, 18)
        lay.setSpacing(12)

        head = QLabel("训练监控")
        head.setObjectName("title")
        sub = QLabel("每个 epoch 自动更新；指标含义见各图下方说明")
        sub.setObjectName("sub")
        lay.addWidget(head); lay.addWidget(sub)

        # 状态条
        srow = QHBoxLayout()
        self.lbl_status = QLabel("等待开始训练…")
        self.lbl_status.setObjectName("stat")
        self.progress = QProgressBar(); self.progress.setRange(0, 100)
        srow.addWidget(self.lbl_status, 1)
        srow.addWidget(self.progress, 2)
        lay.addLayout(srow)

        # 指标图（检测 6 图 / 分类 3 图）
        # 先建宿主容器并把画布挂到它名下，避免无父级的画布变成独立悬浮窗口
        self.grid_host = QWidget()
        self.grid = QGridLayout(self.grid_host)
        self.grid.setSpacing(10)
        self.canvas_box = MetricCanvas("训练损失 Loss", "loss", "#3d8bff", parent=self.grid_host)
        self.canvas_map50 = MetricCanvas("mAP@0.5（核心指标，越高越好）", "mAP50", "#2ecc71", parent=self.grid_host)
        self.canvas_map = MetricCanvas("mAP@0.5:0.95（严格指标）", "mAP", "#9b59b6", parent=self.grid_host)
        self.canvas_p = MetricCanvas("精确率 Precision（误报越少越高）", "precision", "#e67e22", parent=self.grid_host)
        self.canvas_r = MetricCanvas("召回率 Recall（漏检越少越高）", "recall", "#f1c40f", parent=self.grid_host)
        self.canvas_lr = MetricCanvas("学习率", "lr", "#95a5a6", parent=self.grid_host)
        self.canvas_acc = MetricCanvas("分类准确率 Top-1", "acc", "#2ecc71", parent=self.grid_host)
        self.canvas_vloss = MetricCanvas("验证损失（越低越好）", "val loss", "#e74c3c", parent=self.grid_host)

        self._detect_widgets = [
            (self.canvas_box, ("train/box_loss", "train/cls_loss")),
            (self.canvas_vloss, ("val/box_loss", "val/cls_loss")),
            (self.canvas_map50, ("metrics/mAP50(B)",)),
            (self.canvas_map, ("metrics/mAP50-95(B)",)),
            (self.canvas_p, ("metrics/precision(B)",)),
            (self.canvas_r, ("metrics/recall(B)",)),
        ]
        self._classify_widgets = [
            (self.canvas_box, ("train/loss",)),
            (self.canvas_acc, ("metrics/accuracy_top1",)),
            (self.canvas_vloss, ("val/loss",)),
        ]
        for c, *_ in self._detect_widgets:
            c.hide()
        for c, *_ in self._classify_widgets:
            c.hide()
        self.canvas_lr.hide()  # 学习率图暂不参与布局，必须显式隐藏，否则会叠在网格左上角
        lay.addWidget(self.grid_host, 1)

        tips = QLabel(
            "指标说明：Loss 越低越好；mAP@0.5 是最常用的检测精度指标（≥0.75 达标）；"
            "Precision 高=报得准，Recall 高=漏得少；验证集曲线与训练集曲线趋势一致且不发散=训练健康"
        )
        tips.setObjectName("hint")
        tips.setWordWrap(True)
        lay.addWidget(tips)

        self.log = QPlainTextEdit(); self.log.setReadOnly(True)
        self.log.setMaximumHeight(150)
        self.log.setPlaceholderText("训练日志…")
        lay.addWidget(self.log)

        self._mode = "detect"

    def set_mode(self, task):
        self._mode = task
        # box/vloss 两图在检测与分类列表中共用，必须按"是否属于当前模式"一次性
        # 决定显隐，否则第二个循环会把第一个循环刚 show 的共用图再 hide 掉
        active = {c for c, _ in (self._detect_widgets if task == "detect" else self._classify_widgets)}
        for c, _ in self._detect_widgets + self._classify_widgets:
            c.setVisible(c in active)
        self._reflow()

    def _reflow(self):
        widgets = [w for w, cols in (self._detect_widgets if self._mode == "detect" else self._classify_widgets) if not w.isHidden()]
        while self.grid.count():
            self.grid.takeAt(0)
        per = 3
        for i, c in enumerate(widgets):
            self.grid.addWidget(c, i // per, i % per)
        self.grid_host.updateGeometry()

    def append_log(self, text):
        self.log.appendPlainText(text)

    def on_metrics(self, m):
        try:
            ep = int(float(m.get("epoch", 0))) + 1
            total = self.progress.maximum() or 1
            self.lbl_status.setText(f"训练中 · 第 {ep} 轮")
            if self._mode == "detect":
                series = [
                    (self.canvas_box, float(m.get("train/box_loss", 0)), float(m.get("train/cls_loss", 0))),
                    (self.canvas_vloss, float(m.get("val/box_loss", 0)), float(m.get("val/cls_loss", 0))),
                    (self.canvas_map50, float(m.get("metrics/mAP50(B)", 0)), None),
                    (self.canvas_map, float(m.get("metrics/mAP50-95(B)", 0)), None),
                    (self.canvas_p, float(m.get("metrics/precision(B)", 0)), None),
                    (self.canvas_r, float(m.get("metrics/recall(B)", 0)), None),
                ]
            else:
                series = [
                    (self.canvas_box, float(m.get("train/loss", 0)), None),
                    (self.canvas_vloss, float(m.get("val/loss", 0)), None),
                    (self.canvas_acc, float(m.get("metrics/accuracy_top1", 0)), None),
                ]
            for c, v, v2 in series:
                c.x.append(ep); c.y.append(v)
                if v2 is not None:
                    if not c.y2:
                        c.y2 = [None] * (len(c.x) - 1)
                    c.y2.append(v2)
                c.update_data(c.x, c.y, c.y2)
        except Exception:
            pass

    def on_started(self, epochs):
        self.progress.setRange(0, epochs)
        self.progress.setValue(0)
        for c, cols in self._detect_widgets + self._classify_widgets:
            c.x, c.y, c.y2 = [], [], []
            c.update_data([], [])
        self.lbl_status.setText("训练中…")
        self.append_log("=== 训练开始 ===")

    def on_tick(self, ep):
        self.progress.setValue(ep)

    def on_done(self, best_pt):
        self.progress.setValue(self.progress.maximum())
        self.lbl_status.setText(f"✔ 训练完成 · best.pt 已生成")
        self.append_log(f"=== 训练完成 ===\n最优权重：{best_pt}")

    def on_failed(self, err):
        self.lbl_status.setText("✖ 训练失败")
        self.append_log("=== 出错 ===")
        self.append_log(err[-2000:])


class InferPage(QWidget):
    """第三页：模型试跑"""
    def __init__(self, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 18, 24, 18)
        lay.setSpacing(12)

        head = QLabel("模型试跑")
        head.setObjectName("title")
        sub = QLabel("用训练好的权重对图片/文件夹做识别，直观检验效果")
        sub.setObjectName("sub")
        lay.addWidget(head); lay.addWidget(sub)

        g = QGroupBox("试跑设置")
        f = QGridLayout(g)
        f.setVerticalSpacing(10)
        f.addWidget(QLabel("权重文件"), 0, 0)
        self.weights = QLineEdit()
        f.addWidget(self.weights, 0, 1)
        b1 = QPushButton("选择..."); b1.setObjectName("ghost")
        b1.clicked.connect(self._pick_weights)
        f.addWidget(b1, 0, 2)
        f.addWidget(QLabel("测试图片/文件夹"), 1, 0)
        self.source = QLineEdit()
        f.addWidget(self.source, 1, 1)
        b2 = QPushButton("选择..."); b2.setObjectName("ghost")
        b2.clicked.connect(self._pick_source)
        f.addWidget(b2, 1, 2)
        f.addWidget(QLabel("置信度阈值"), 2, 0)
        self.conf = QComboBox()
        for c in ("0.25", "0.40", "0.50", "0.60"):
            self.conf.addItem(c, float(c))
        self.conf.setCurrentIndex(2)
        f.addWidget(self.conf, 2, 1)
        self.btn_run = QPushButton("▶  开始试跑")
        self.btn_run.setMinimumHeight(40)
        self.btn_run.clicked.connect(self._run)
        f.addWidget(self.btn_run, 2, 2)
        lay.addWidget(g)

        split = QSplitter(Qt.Horizontal)
        self.listw = QListWidget()
        self.listw.currentItemChanged.connect(self._show_item)
        self.preview = QLabel("试跑结果预览")
        self.preview.setAlignment(Qt.AlignCenter)
        self.preview.setMinimumSize(420, 420)
        self.preview.setStyleSheet("background:#101218;border:1px solid #2c313c;border-radius:8px;color:#8b93a1;")
        split.addWidget(self.listw)
        split.addWidget(self.preview)
        split.setSizes([360, 760])
        lay.addWidget(split, 1)

        self.lbl_out = QLabel("")
        self.lbl_out.setObjectName("hint")
        lay.addWidget(self.lbl_out)

        self._items = {}
        self._worker = None

    def set_default_weights(self, p):
        self.weights.setText(p)

    def _pick_weights(self):
        f, _ = QFileDialog.getOpenFileName(self, "选择权重", RUNS_DIR, "模型权重 (*.pt)")
        if f:
            self.weights.setText(f)

    def _pick_source(self):
        d = QFileDialog.getExistingDirectory(self, "选择测试图片文件夹")
        if d:
            self.source.setText(d)
            return
        f, _ = QFileDialog.getOpenFileName(self, "选择测试图片", "", "图片 (*.jpg *.jpeg *.png *.bmp)")
        if f:
            self.source.setText(f)

    def _run(self):
        w, s = self.weights.text().strip(), self.source.text().strip()
        if not os.path.isfile(w):
            QMessageBox.warning(self, "权重无效", "请选择有效的 .pt 权重文件")
            return
        if not os.path.exists(s):
            QMessageBox.warning(self, "路径无效", "请选择有效的图片或文件夹")
            return
        self.listw.clear(); self._items.clear()
        self.btn_run.setEnabled(False)
        self._worker = InferWorker(w, s, RUNS_DIR, self.conf.currentData())
        self._worker.one_result.connect(self._on_one)
        self._worker.finished_ok.connect(self._on_done)
        self._worker.failed.connect(self._on_fail)
        self._worker.start()

    def _on_one(self, path, n):
        label = f"{os.path.basename(path)}   ·   {'检出 %d 个目标' % n if n >= 0 else ''}"
        it = QListWidgetItem(label)
        self._items[it] = path
        self.listw.addItem(it)

    def _on_done(self, out_dir):
        self.btn_run.setEnabled(True)
        self.lbl_out.setText(f"结果图已保存：{out_dir}")
        if self.listw.count():
            self.listw.setCurrentRow(0)

    def _on_fail(self, err):
        self.btn_run.setEnabled(True)
        QMessageBox.critical(self, "试跑失败", err[-800:])

    def _show_item(self, cur, _):
        if not cur:
            return
        path = self._items.get(cur)
        if path and os.path.isfile(path):
            img = QImage(path)
            if not img.isNull():
                pm = QPixmap.fromImage(img).scaled(
                    self.preview.width(), self.preview.height(),
                    Qt.KeepAspectRatio, Qt.SmoothTransformation)
                self.preview.setPixmap(pm)


class ExportPage(QWidget):
    """第四页：导出部署"""
    def __init__(self, parent=None):
        super().__init__(parent)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(24, 18, 24, 18)
        lay.setSpacing(12)

        head = QLabel("导出部署")
        head.setObjectName("title")
        sub = QLabel("训练完成后导出为 APP 可用的格式（TFLite int8 供手机端推理）")
        sub.setObjectName("sub")
        lay.addWidget(head); lay.addWidget(sub)

        g = QGroupBox("导出设置")
        f = QGridLayout(g)
        f.addWidget(QLabel("权重文件"), 0, 0)
        self.weights = QLineEdit()
        f.addWidget(self.weights, 0, 1)
        b = QPushButton("选择..."); b.setObjectName("ghost")
        b.clicked.connect(self._pick)
        f.addWidget(b, 0, 2)
        f.addWidget(QLabel("导出格式"), 1, 0)
        self.fmt = QComboBox()
        self.fmt.addItem("TFLite int8（手机 APP 端推荐）", "tflite")
        self.fmt.addItem("ONNX（通用中间格式）", "onnx")
        f.addWidget(self.fmt, 1, 1, 1, 2)
        self.btn = QPushButton("⬇  开始导出")
        self.btn.setMinimumHeight(40)
        self.btn.clicked.connect(self._run)
        f.addWidget(self.btn, 2, 0, 1, 3)
        lay.addWidget(g)

        self.log = QPlainTextEdit(); self.log.setReadOnly(True)
        self.log.setPlaceholderText("导出日志…")
        lay.addWidget(self.log, 1)

        self.lbl_done = QLabel("")
        self.lbl_done.setObjectName("stat")
        lay.addWidget(self.lbl_done)
        self._worker = None

    def set_default_weights(self, p):
        self.weights.setText(p)

    def _pick(self):
        f, _ = QFileDialog.getOpenFileName(self, "选择权重", RUNS_DIR, "模型权重 (*.pt)")
        if f:
            self.weights.setText(f)

    def _run(self):
        w = self.weights.text().strip()
        if not os.path.isfile(w):
            QMessageBox.warning(self, "权重无效", "请选择有效的 .pt 权重文件")
            return
        self.btn.setEnabled(False)
        self.lbl_done.setText("")
        self._worker = ExportWorker(w, self.fmt.currentData())
        self._worker.log_line.connect(self.log.appendPlainText)
        self._worker.finished_ok.connect(self._done)
        self._worker.failed.connect(self._fail)
        self._worker.start()

    def _done(self, path):
        self.btn.setEnabled(True)
        self.lbl_done.setText(f"✔ 导出完成：{path}")

    def _fail(self, err):
        self.btn.setEnabled(True)
        self.log.appendPlainText("=== 导出出错 ===")
        self.log.appendPlainText(err[-1500:])


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(f"护花使者 · 虫害识别模型训练器 {APP_VERSION}")
        self.resize(1180, 780)
        self.train_worker = None

        tabs = QTabWidget()
        self.setCentralWidget(tabs)

        self.page_cfg = TrainConfigPage(self._start_train)
        self.page_mon = TrainMonitorPage()
        self.page_inf = InferPage()
        self.page_exp = ExportPage()
        tabs.addTab(self.page_cfg, "  ① 训练配置  ")
        tabs.addTab(self.page_mon, "  ② 实时监控  ")
        tabs.addTab(self.page_inf, "  ③ 模型试跑  ")
        tabs.addTab(self.page_exp, "  ④ 导出部署  ")

        # 自动填最近一次 best.pt
        self._auto_fill_best()

    def _auto_fill_best(self):
        if not os.path.isdir(RUNS_DIR):
            return
        bests = []
        for root, dirs, files in os.walk(RUNS_DIR):
            if "best.pt" in files:
                bests.append(os.path.join(root, "best.pt"))
        if bests:
            latest = max(bests, key=os.path.getmtime)
            self.page_inf.set_default_weights(latest)
            self.page_exp.set_default_weights(latest)

    # ---------- 训练 ----------
    def _start_train(self, cfg):
        tabs = self.centralWidget()
        self.page_mon.set_mode(cfg["task"])
        self.page_mon.on_started(cfg["epochs"])
        tabs.setCurrentWidget(self.page_mon)

        self.train_worker = TrainWorker(
            task=cfg["task"], model_size=cfg["size"], data_root=cfg["data"],
            project_dir=RUNS_DIR, name=cfg["name"], epochs=cfg["epochs"],
            imgsz=cfg["imgsz"], batch=cfg["batch"], device=cfg["device"],
        )
        self._current_run_name = cfg["name"]
        self.train_worker.log_line.connect(self.page_mon.append_log)
        self.train_worker.metrics.connect(self.page_mon.on_metrics)
        self.train_worker.finished_ok.connect(self._train_done)
        self.train_worker.failed.connect(self.page_mon.on_failed)
        self.page_cfg.btn_start.setEnabled(False)
        self.train_worker.start()

        # 进度条随 epoch 走
        self._ep_timer = QTimer(self)
        self._ep_timer.timeout.connect(self._tick_epoch)
        self._ep_timer.start(2000)

    def _tick_epoch(self):
        csv_path = os.path.join(RUNS_DIR, getattr(self, "_current_run_name", ""), "results.csv")
        try:
            with open(csv_path, "r", encoding="utf-8") as f:
                n = sum(1 for _ in f)
            self.page_mon.on_tick(max(0, n - 1))
        except OSError:
            pass

    def _train_done(self, best_pt):
        self.page_cfg.btn_start.setEnabled(True)
        self.page_mon.on_done(best_pt)
        self._ep_timer.stop()
        self.page_inf.set_default_weights(best_pt)
        self.page_exp.set_default_weights(best_pt)
        QMessageBox.information(
            self, "训练完成",
            f"最优权重已生成：\n{best_pt}\n\n可到「③ 模型试跑」检验效果，"
            "再到「④ 导出部署」导出 TFLite 供 APP 使用。"
        )


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setFont(QFont("Microsoft YaHei UI", 10))
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
