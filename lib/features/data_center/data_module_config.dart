import 'package:flutter/material.dart';

/// 字段类型
enum FieldType { text, number, date, multiline, select }

/// 字段配置
class FieldConfig {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? hint;
  final List<String>? options; // 用于select类型

  const FieldConfig({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.hint,
    this.options,
  });
}

/// 数据模块配置
class DataModuleConfig {
  final String moduleKey;
  final String moduleName;
  final IconData icon;
  final Color color;
  final List<FieldConfig> fields;
  final List<String> searchFields;
  final String storageKey;
  final String description;

  const DataModuleConfig({
    required this.moduleKey,
    required this.moduleName,
    required this.icon,
    required this.color,
    required this.fields,
    required this.searchFields,
    required this.storageKey,
    this.description = '',
  });
}

/// 11个PC端数据管理模块配置
class DataModules {
  DataModules._();

  static const List<DataModuleConfig> allModules = [
    // 1. 油菜种植地块信息
    DataModuleConfig(
      moduleKey: 'field',
      moduleName: '地块管理',
      icon: Icons.terrain,
      color: Color(0xFF4CAF50),
      storageKey: 'data_fields',
      description: '管理油菜种植地块信息，记录编号、面积、种植日期',
      fields: [
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'field_name', label: '地块名称', required: true, hint: '如: 王家村东片'),
        FieldConfig(key: 'area', label: '地块面积(亩)', type: FieldType.number, required: true, hint: '如: 15.5'),
        FieldConfig(key: 'planting_date', label: '种植日期', type: FieldType.date, hint: '如: 2025-10-15'),
      ],
      searchFields: ['field_code', 'field_name', 'area', 'planting_date'],
    ),

    // 2. 植保无人机设备信息
    DataModuleConfig(
      moduleKey: 'drone',
      moduleName: '无人机管理',
      icon: Icons.flight,
      color: Color(0xFF2196F3),
      storageKey: 'data_drones',
      description: '管理植保无人机设备，记录型号、药箱容量、续航',
      fields: [
        FieldConfig(key: 'drone_code', label: '无人机编号', required: true, hint: '如: DJI-T40-001'),
        FieldConfig(key: 'model_name', label: '型号名称', required: true, hint: '如: 大疆T40'),
        FieldConfig(key: 'tank_capacity', label: '药箱容量(升)', type: FieldType.number, required: true, hint: '如: 40'),
        FieldConfig(key: 'flight_time', label: '续航时间(分钟)', type: FieldType.number, required: true, hint: '如: 25'),
      ],
      searchFields: ['drone_code', 'model_name', 'tank_capacity', 'flight_time'],
    ),

    // 3. 农药信息配置管理
    DataModuleConfig(
      moduleKey: 'pesticide',
      moduleName: '农药管理',
      icon: Icons.science,
      color: Color(0xFFFF5722),
      storageKey: 'data_pesticides',
      description: '管理农药信息，记录施用比例、稀释比例',
      fields: [
        FieldConfig(key: 'pesticide_code', label: '农药编号', required: true, hint: '如: NY-001'),
        FieldConfig(key: 'pesticide_name', label: '农药名称', required: true, hint: '如: 吡虫啉'),
        FieldConfig(key: 'application_rate', label: '施用比例(ml/亩)', type: FieldType.number, required: true, hint: '如: 30'),
        FieldConfig(key: 'dilution_ratio', label: '稀释比例', hint: '如: 1:1000'),
      ],
      searchFields: ['pesticide_code', 'pesticide_name', 'application_rate', 'dilution_ratio'],
    ),

    // 4. 油菜生长阶段监测
    DataModuleConfig(
      moduleKey: 'growth',
      moduleName: '生长监测',
      icon: Icons.eco,
      color: Color(0xFF8BC34A),
      storageKey: 'data_growth',
      description: '记录油菜各生长阶段，苗期、蕾薹、开花、结荚、成熟',
      fields: [
        FieldConfig(key: 'stage_code', label: '阶段编号', required: true, hint: '如: GS-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(
          key: 'growth_stage',
          label: '生长阶段',
          type: FieldType.select,
          required: true,
          options: ['苗期', '蕾薹期', '开花期', '结荚期', '成熟期'],
        ),
        FieldConfig(key: 'observation_date', label: '观测日期', type: FieldType.date, hint: '如: 2025-11-01'),
      ],
      searchFields: ['stage_code', 'field_code', 'growth_stage', 'observation_date'],
    ),

    // 5. 病虫害识别记录
    DataModuleConfig(
      moduleKey: 'pest',
      moduleName: '病虫害记录',
      icon: Icons.bug_report,
      color: Color(0xFFE91E63),
      storageKey: 'data_pests',
      description: '记录病虫害信息，菌核病、蚜虫等，标记严重程度',
      fields: [
        FieldConfig(key: 'disease_code', label: '病害编号', required: true, hint: '如: PD-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'disease_name', label: '病害名称', required: true, hint: '如: 菌核病'),
        FieldConfig(
          key: 'severity',
          label: '严重程度',
          type: FieldType.select,
          required: true,
          options: ['轻度', '中度', '重度', '特重'],
        ),
      ],
      searchFields: ['disease_code', 'field_code', 'disease_name', 'severity'],
    ),

    // 6. 飞行路径规划记录
    DataModuleConfig(
      moduleKey: 'flight_path',
      moduleName: '飞行路径',
      icon: Icons.route,
      color: Color(0xFF9C27B0),
      storageKey: 'data_flight_paths',
      description: '规划无人机飞行路径，记录坐标序列和飞行高度',
      fields: [
        FieldConfig(key: 'path_code', label: '路径编号', required: true, hint: '如: FP-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'coordinates', label: '路径坐标序列', type: FieldType.multiline, hint: '如: 30.5,114.3;30.6,114.4'),
        FieldConfig(key: 'altitude', label: '飞行高度(米)', type: FieldType.number, required: true, hint: '如: 3'),
      ],
      searchFields: ['path_code', 'field_code', 'coordinates', 'altitude'],
    ),

    // 7. 喷洒作业执行记录
    DataModuleConfig(
      moduleKey: 'spray_job',
      moduleName: '作业记录',
      icon: Icons.water_drop,
      color: Color(0xFF00BCD4),
      storageKey: 'data_spray_jobs',
      description: '记录植保喷洒作业，关联无人机、地块、作业时间',
      fields: [
        FieldConfig(key: 'job_code', label: '作业编号', required: true, hint: '如: SJ-001'),
        FieldConfig(key: 'drone_code', label: '无人机编号', required: true, hint: '如: DJI-T40-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'job_time', label: '作业时间', type: FieldType.date, hint: '如: 2025-11-15'),
      ],
      searchFields: ['job_code', 'drone_code', 'field_code', 'job_time'],
    ),

    // 8. 气象环境数据监测
    DataModuleConfig(
      moduleKey: 'weather_data',
      moduleName: '气象数据',
      icon: Icons.cloud,
      color: Color(0xFF607D8B),
      storageKey: 'data_weathers',
      description: '监测田间气象环境，记录温度、风速等数据',
      fields: [
        FieldConfig(key: 'weather_code', label: '气象编号', required: true, hint: '如: WX-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'temperature', label: '温度(℃)', type: FieldType.number, required: true, hint: '如: 25'),
        FieldConfig(key: 'wind_speed', label: '风速(m/s)', type: FieldType.number, required: true, hint: '如: 3.5'),
      ],
      searchFields: ['weather_code', 'field_code', 'temperature', 'wind_speed'],
    ),

    // 9. 一键适配参数配置
    DataModuleConfig(
      moduleKey: 'adapter',
      moduleName: '一键适配',
      icon: Icons.auto_fix_high,
      color: Color(0xFFFF9800),
      storageKey: 'data_adapters',
      description: '根据生长阶段自动推荐农药配方和飞行参数',
      fields: [
        FieldConfig(key: 'config_code', label: '配置编号', required: true, hint: '如: AD-001'),
        FieldConfig(
          key: 'growth_stage',
          label: '生长阶段',
          type: FieldType.select,
          required: true,
          options: ['苗期', '蕾薹期', '开花期', '结荚期', '成熟期'],
        ),
        FieldConfig(key: 'recommended_pesticide', label: '推荐农药', required: true, hint: '如: 吡虫啉+多菌灵'),
        FieldConfig(key: 'flight_speed', label: '飞行速度(m/s)', type: FieldType.number, required: true, hint: '如: 4'),
      ],
      searchFields: ['config_code', 'growth_stage', 'recommended_pesticide', 'flight_speed'],
    ),

    // 10. 操作员日志记录
    DataModuleConfig(
      moduleKey: 'operation_log',
      moduleName: '操作日志',
      icon: Icons.assignment,
      color: Color(0xFF795548),
      storageKey: 'data_operation_logs',
      description: '记录操作员喷洒、维护、数据录入等操作日志',
      fields: [
        FieldConfig(key: 'log_code', label: '日志编号', required: true, hint: '如: LOG-001'),
        FieldConfig(key: 'operator_name', label: '操作员姓名', required: true, hint: '如: 张三'),
        FieldConfig(
          key: 'operation_type',
          label: '操作类型',
          type: FieldType.select,
          required: true,
          options: ['喷洒作业', '设备维护', '数据录入', '参数调整', '其他'],
        ),
        FieldConfig(key: 'operation_time', label: '操作时间', type: FieldType.date, hint: '如: 2025-11-15'),
      ],
      searchFields: ['log_code', 'operator_name', 'operation_type', 'operation_time'],
    ),

    // 11. 农情分析报告管理
    DataModuleConfig(
      moduleKey: 'report',
      moduleName: '分析报告',
      icon: Icons.assessment,
      color: Color(0xFF3F51B5),
      storageKey: 'data_reports',
      description: '生成农情分析报告，关联地块和历史数据',
      fields: [
        FieldConfig(key: 'report_code', label: '报告编号', required: true, hint: '如: RP-001'),
        FieldConfig(key: 'field_code', label: '地块编号', required: true, hint: '如: YC-001'),
        FieldConfig(key: 'report_title', label: '报告标题', required: true, hint: '如: 王家村东片12月农情分析'),
        FieldConfig(key: 'report_date', label: '生成日期', type: FieldType.date, hint: '如: 2025-12-01'),
      ],
      searchFields: ['report_code', 'field_code', 'report_title', 'report_date'],
    ),
  ];
}