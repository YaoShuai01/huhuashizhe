import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/growth_record_store.dart';
import 'growth_record_detail_page.dart';

/// 病虫害记录：以列表卡形式展示每一次模型测试识别记录
/// 卡片命名：地区（某某市某某县/区）+ 时间戳
class GrowthRecordsPage extends StatefulWidget {
  const GrowthRecordsPage({super.key});

  @override
  State<GrowthRecordsPage> createState() => _GrowthRecordsPageState();
}

class _GrowthRecordsPageState extends State<GrowthRecordsPage> {
  final GrowthRecordStore _store = GrowthRecordStore();
  List<GrowthRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _records = _store.getAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('病虫害记录')),
      body: _records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.bug_report, size: 64, color: AppColors.textDisabled),
                  SizedBox(height: 12),
                  Text('暂无病虫害记录',
                      style: TextStyle(color: AppColors.textHint, fontSize: 15)),
                  SizedBox(height: 4),
                  Text('在首页进入"模型测试"进行一次实时识别后自动同步',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                itemCount: _records.length,
                itemBuilder: (context, index) {
                  final record = _records[index];
                  return _buildRecordCard(record);
                },
              ),
            ),
    );
  }

  Widget _buildRecordCard(GrowthRecord record) {
    final problemNames = record.problems.map((p) => p.zhName).toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GrowthRecordDetailPage(recordId: record.id),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF8BC34A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.eco,
                    color: Color(0xFF8BC34A), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      problemNames.isEmpty
                          ? '未识别到问题 · ${record.totalImages} 张采集图'
                          : '${problemNames.take(3).join('、')}${problemNames.length > 3 ? ' 等${problemNames.length}项' : ''}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (record.aiPending)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('AI待生成',
                      style: TextStyle(fontSize: 10, color: AppColors.accent)),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
