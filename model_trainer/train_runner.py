# -*- coding: utf-8 -*-
"""独立训练子进程脚本：由训练器界面以 python train_runner.py <config.json> 方式启动。

设计动机：
1. ultralytics 的多进程数据加载在"界面进程内的线程"里会死锁（实测所有进程 CPU 归零），
   在本独立脚本（轻量 __main__、无 Qt）里则完全正常，8 进程加载可稳定拉起；
2. 训练崩溃不再波及界面进程，界面只当"监工"读日志和 results.csv。

输出约定：正常打印训练日志（ultralytics 原生 stdout），结束前打印 "BEST_PT <路径>"，
退出码 0=成功、1=失败。父进程通过 taskkill /T 停止本进程树实现"立即停止"。
"""
import json
import os
import sys
import traceback


def resolve_model_path(model_size, task="detect"):
    """优先使用工具目录内自带的预训练权重（避免运行时从 GitHub 下载被 403 限流）。
    分类任务必须用 -cls 后缀权重。"""
    suffix = "-cls" if task == "classify" else ""
    base = os.path.dirname(os.path.abspath(__file__))
    for cand in (
        os.path.join(base, f"yolo11{model_size}{suffix}.pt"),
        os.path.join(base, "weights", f"yolo11{model_size}{suffix}.pt"),
    ):
        if os.path.isfile(cand):
            return cand
    return f"yolo11{model_size}{suffix}.pt"


def prepare_detection_data(root):
    """检测数据集：约定根目录下 train/images、train/labels、val/images、val/labels，
    类别名从根目录 classes.txt 读取（每行一个）。生成 data.yaml。返回 (yaml路径, 类别数)。"""
    import yaml

    root = os.path.abspath(root)
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


def prepare_classify_data(root):
    """分类数据集：约定根目录下 train/<类别名>/*.图片、val/<类别名>/*.图片"""
    root = os.path.abspath(root)
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


def _disable_pin_memory():
    """关闭 DataLoader 的 pinned memory（cudaHostRegister）。
    本机 WDDM 环境实测会出现 CUDA "resource already mapped" 崩溃（驱动层固定内存映射冲突），
    对训练速度影响极小（多进程喂数补偿），关闭更稳。"""
    import functools
    import importlib
    import ultralytics.data.build as _ub

    orig = _ub.build_dataloader

    @functools.wraps(orig)
    def _wrapped(*a, **kw):
        kw["pin_memory"] = False
        return orig(*a, **kw)

    _ub.build_dataloader = _wrapped
    for mod_name in ("ultralytics.models.yolo.classify.train",
                     "ultralytics.models.yolo.detect.train",
                     "ultralytics.models.yolo.segment.train",
                     "ultralytics.models.yolo.pose.train",
                     "ultralytics.models.yolo.obb.train"):
        try:
            mod = importlib.import_module(mod_name)
            if getattr(mod, "build_dataloader", None) is not None:
                mod.build_dataloader = _wrapped
        except Exception:
            pass


def main():
    if len(sys.argv) < 2:
        print("用法: python train_runner.py <config.json>")
        return 1
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        cfg = json.load(f)

    task = cfg["task"]
    print("正在初始化训练环境（首次运行会自动下载预训练权重）...", flush=True)
    from ultralytics import YOLO

    _disable_pin_memory()

    if task == "detect":
        data, ncls = prepare_detection_data(cfg["data_root"])
        print(f"检测数据集就绪：{ncls} 个类别", flush=True)
    else:
        data, _ = prepare_classify_data(cfg["data_root"])
        print("分类数据集就绪", flush=True)

    model_name = resolve_model_path(cfg["model_size"], task)
    print(f"加载基础模型：{model_name}", flush=True)
    model = YOLO(model_name)

    # 多进程数据加载数：独立进程内无死锁风险，默认 8 进程喂饱 GPU
    try:
        workers = max(0, int(os.environ.get("HHS_FORCE_WORKERS", "8")))
    except ValueError:
        workers = 8

    batch = int(cfg.get("batch") or 0)
    model.train(
        data=data,
        epochs=int(cfg["epochs"]),
        imgsz=int(cfg["imgsz"]),
        batch=batch if batch > 0 else -1,
        project=os.path.abspath(cfg["project_dir"]),
        name=cfg["name"],
        exist_ok=True,
        device=None if cfg.get("device") in ("", "auto", None) else cfg["device"],
        workers=workers,
        plots=True,
        patience=50,
    )
    best = os.path.join(os.path.abspath(cfg["project_dir"]), cfg["name"], "weights", "best.pt")
    print(f"BEST_PT {best}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception:
        traceback.print_exc()
        sys.exit(1)
