import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local_database.dart';
import '../data_module_config.dart';

/// 通用数据列表页面 - 基于配置驱动，适配所有PC端数据管理模块
class DataListPage extends StatefulWidget {
  final DataModuleConfig config;

  const DataListPage({super.key, required this.config});

  @override
  State<DataListPage> createState() => _DataListPageState();
}

class _DataListPageState extends State<DataListPage> {
  final _db = LocalDatabase();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _allData = [];
  List<Map<String, dynamic>> _filteredData = [];
  bool _loading = true;

  DataModuleConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() => _loading = true);
    _allData = _db.getDataList(_config.storageKey);
    _filteredData = List.from(_allData);
    _searchController.clear();
    setState(() => _loading = false);
  }

  void _search(String keyword) {
    if (keyword.isEmpty) {
      _filteredData = List.from(_allData);
    } else {
      final kw = keyword.toLowerCase();
      _filteredData = _allData.where((item) {
        for (final field in _config.searchFields) {
          final value = (item[field] ?? '').toString().toLowerCase();
          if (value.contains(kw)) return true;
        }
        return false;
      }).toList();
    }
    setState(() {});
  }

  void _deleteItem(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: const Text('确定删除此信息？删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              _db.deleteDataItem(_config.storageKey, id);
              _loadData();
              Navigator.pop(ctx);
              _showSnackBar('删除成功');
            },
            child: const Text('确定', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _displayValue(Map<String, dynamic> item, FieldConfig field) {
    final value = item[field.key];
    if (value == null || value.toString().isEmpty) return '--';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_config.moduleName),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DataFormPage(config: _config),
                ),
              );
              if (result == true) _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: '搜索${_config.moduleName}...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textHint),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_config.icon, size: 64, color: AppColors.textDisabled),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty ? '未找到匹配数据' : '暂无数据',
                              style: const TextStyle(color: AppColors.textHint, fontSize: 15),
                            ),
                            if (_searchController.text.isEmpty) ...[
                              const SizedBox(height: 4),
                              const Text('点击右上角 + 添加数据', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _loadData(),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 20),
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final item = _filteredData[index];
                            return _buildDataCard(item);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DataFormPage(config: _config, existingData: item),
            ),
          );
          if (result == true) _loadData();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：主要标识信息
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _config.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_config.icon, color: _config.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayValue(item, _config.fields[0]),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_config.fields.length > 1)
                          Text(
                            _displayValue(item, _config.fields[1]),
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppColors.textHint, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DataFormPage(config: _config, existingData: item),
                          ),
                        ).then((r) => r == true ? _loadData() : null);
                      } else if (value == 'delete') {
                        _deleteItem(item['id']);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18, color: AppColors.primary), SizedBox(width: 8), Text('编辑')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: AppColors.error), SizedBox(width: 8), Text('删除')])),
                    ],
                  ),
                ],
              ),
              // 其余字段信息
              if (_config.fields.length > 2) ...[
                const Divider(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: _config.fields.skip(2).map((field) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${field.label}: ', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                        Text(
                          _displayValue(item, field),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用数据表单页面 - 添加/编辑
class DataFormPage extends StatefulWidget {
  final DataModuleConfig config;
  final Map<String, dynamic>? existingData;

  const DataFormPage({super.key, required this.config, this.existingData});

  @override
  State<DataFormPage> createState() => _DataFormPageState();
}

class _DataFormPageState extends State<DataFormPage> {
  final _db = LocalDatabase();
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String?> _selectValues;

  DataModuleConfig get _config => widget.config;
  bool get _isEditing => widget.existingData != null;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _selectValues = {};
    for (final field in _config.fields) {
      final value = widget.existingData?[field.key]?.toString() ?? '';
      _controllers[field.key] = TextEditingController(text: value);
      if (field.type == FieldType.select) {
        _selectValues[field.key] = value.isNotEmpty ? value : null;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final data = <String, dynamic>{};
    for (final field in _config.fields) {
      if (field.type == FieldType.select) {
        data[field.key] = _selectValues[field.key] ?? '';
      } else {
        data[field.key] = _controllers[field.key]!.text.trim();
      }
    }

    if (_isEditing) {
      _db.updateDataItem(_config.storageKey, widget.existingData!['id'], data);
    } else {
      _db.addDataItem(_config.storageKey, data);
    }

    Navigator.pop(context, true);
  }

  Future<void> _pickDate(FieldConfig field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _controllers[field.key]!.text = dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑${_config.moduleName}' : '添加${_config.moduleName}'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 模块图标标题
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _config.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_config.icon, color: _config.color, size: 32),
                ),
              ),
              const SizedBox(height: 24),
              // 表单字段
              ..._config.fields.map((field) => _buildField(field)),
              const SizedBox(height: 24),
              // 保存按钮
              ElevatedButton(
                onPressed: _save,
                child: Text(_isEditing ? '保存修改' : '添加数据'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消'),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(FieldConfig field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${field.label}${field.required ? ' *' : ''}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          _buildFieldInput(field),
        ],
      ),
    );
  }

  Widget _buildFieldInput(FieldConfig field) {
    switch (field.type) {
      case FieldType.select:
        return DropdownButtonFormField<String>(
          value: _selectValues[field.key],
          decoration: _inputDecoration(field.hint ?? '请选择${field.label}'),
          items: field.options!.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
          onChanged: (val) => setState(() => _selectValues[field.key] = val),
          validator: field.required ? (val) => val == null || val.isEmpty ? '请选择${field.label}' : null : null,
        );

      case FieldType.number:
        return TextFormField(
          controller: _controllers[field.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          decoration: _inputDecoration(field.hint ?? '请输入${field.label}'),
          validator: field.required ? (val) => (val == null || val.trim().isEmpty) ? '请输入${field.label}' : null : null,
        );

      case FieldType.date:
        return TextFormField(
          controller: _controllers[field.key],
          readOnly: true,
          onTap: () => _pickDate(field),
          decoration: _inputDecoration(field.hint ?? '点击选择日期').copyWith(
            suffixIcon: const Icon(Icons.calendar_today, color: AppColors.textHint, size: 20),
          ),
          validator: field.required ? (val) => (val == null || val.trim().isEmpty) ? '请选择${field.label}' : null : null,
        );

      case FieldType.multiline:
        return TextFormField(
          controller: _controllers[field.key],
          maxLines: 3,
          decoration: _inputDecoration(field.hint ?? '请输入${field.label}'),
          validator: field.required ? (val) => (val == null || val.trim().isEmpty) ? '请输入${field.label}' : null : null,
        );

      case FieldType.text:
        return TextFormField(
          controller: _controllers[field.key],
          decoration: _inputDecoration(field.hint ?? '请输入${field.label}'),
          validator: field.required ? (val) => (val == null || val.trim().isEmpty) ? '请输入${field.label}' : null : null,
        );
    }
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: false,
    );
  }
}