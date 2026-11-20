# -*- coding: utf-8 -*-
"""
生成《护花使者APP 技术选型方案》Excel表格
基于原始技术选型表结构，替换为护花使者APP当前/规划技术栈
"""
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

OUTPUT_PATH = r"C:\Users\user\Desktop\护花使者APP_技术选型方案_v2.xlsx"

# 样式定义
HEADER_FILL = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
HEADER_FONT = Font(bold=True, color="FFFFFF", size=12)
TITLE_FONT = Font(bold=True, size=16, color="1F4E78")
BORDER = Border(
    left=Side(style="thin"),
    right=Side(style="thin"),
    top=Side(style="thin"),
    bottom=Side(style="thin"),
)


def set_column_widths(ws, widths):
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w


def style_header_row(ws, row):
    for cell in ws[row]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = BORDER


def style_data_rows(ws, start_row, end_row, cols):
    for r in range(start_row, end_row + 1):
        for c in range(1, cols + 1):
            cell = ws.cell(row=r, column=c)
            cell.border = BORDER
            cell.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)


def create_main_sheet(wb):
    ws = wb.active
    ws.title = "技术选型"

    # 标题
    ws.merge_cells("A1:C1")
    ws["A1"] = "护花使者APP 技术选型"
    ws["A1"].font = TITLE_FONT
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 32

    # 表头
    headers = ["技术维度", "选型 / 工具", "核心作用"]
    ws.append(headers)
    style_header_row(ws, 2)

    # 数据行：基于原始表结构，替换为当前实际技术
    rows = [
        [
            "开发语言",
            "Dart（Flutter APP）\nC/C++（ESP32-S3 飞控固件）",
            "Dart 实现跨平台手机 APP 界面与业务逻辑；C/C++ 保证飞控实时性，直接操作 ESP32 硬件定时器、PWM、GPIO"
        ],
        [
            "通信协议",
            "当前：WiFi UDP（验证阶段）\n规划：蓝牙 4.2/5.0（手机↔手持遥控器）\n规划：数传电台 915MHz/2.4GHz（遥控器↔无人机）",
            "WiFi UDP 用于室内/桌面调试验证；蓝牙保证手机不断网、免 OTG、兼容性好；数传电台提供 1-5km 空地通信距离，满足植保作业"
        ],
        [
            "数据存储",
            "边缘端：JSON 文件（path_provider 文档目录）\n规划云端：MySQL / PostgreSQL + RESTful API",
            "JSON 文件存储用户配置、航线、飞行记录，应用更新不丢失；云端数据库用于多机协同、历史数据、远程诊断"
        ],
        [
            "核心算法",
            "1. 飞行状态机（FSM）：IDLE / ARMED / TAKING_OFF / HOVERING / FLYING / LANDING\n2. PID 控制：高度保持、姿态稳定\n3. X 型四旋翼矢量混控矩阵\n4. 航点规划与路径插值（规划中）",
            "实现解锁-起飞-悬停-飞行-降落全阶段安全切换；厘米级高度控制；标准 Betaflight/ArduPilot 混控逻辑；支持自动航线作业"
        ],
        [
            "AI 推理框架",
            "云端 LLM API（当前）\n规划中：YOLOv8 / ONNX Runtime（边缘端轻量化）",
            "当前通过云端大模型结合定位、天气提供作业建议；未来在机载或地面端部署长势识别、病虫害检测"
        ],
        [
            "飞控开发套件",
            "ESP32-S3 自研飞控平台（ESP-IDF v5.3.1）\nLEDC PWM 电机驱动\n北斗+GPS 双模定位",
            "基于开源硬件自主可控，避免依赖大疆 OSDK / PX4 封闭接口；ESP32-S3 内置 WiFi/蓝牙，便于验证和后续扩展"
        ],
    ]
    for row in rows:
        ws.append(row)

    set_column_widths(ws, [18, 48, 62])
    style_data_rows(ws, 3, 2 + len(rows), 3)

    # 备注行
    note_row = 2 + len(rows) + 2
    ws.merge_cells(f"A{note_row}:C{note_row}")
    ws.cell(row=note_row, column=1, value="备注：当前处于技术验证阶段，通信链路为 WiFi UDP 直连；真实植保作业需演进为\"蓝牙 + 手持遥控器 + 数传电台\"架构。")
    ws.cell(row=note_row, column=1).font = Font(italic=True, color="666666")


def main():
    wb = openpyxl.Workbook()
    create_main_sheet(wb)
    wb.save(OUTPUT_PATH)
    print(f"已生成：{OUTPUT_PATH}")


if __name__ == "__main__":
    main()
