import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/schedule_models.dart';

/// 自定义顺延顺序：先搭好成员序列，再回到编辑页选择日期区间
class ScheduleRotationOrderPage extends StatefulWidget {
  final List<ScheduleMember> members;
  final List<String> initial;

  const ScheduleRotationOrderPage({
    super.key,
    required this.members,
    required this.initial,
  });

  @override
  State<ScheduleRotationOrderPage> createState() =>
      _ScheduleRotationOrderPageState();
}

class _ScheduleRotationOrderPageState extends State<ScheduleRotationOrderPage> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    final ids = widget.members.map((m) => m.id).toSet();
    _order = widget.initial.where(ids.contains).toList();
  }

  ScheduleMember? _member(String id) {
    for (final member in widget.members) {
      if (member.id == id) return member;
    }
    return null;
  }

  int _countOf(String id) => _order.where((e) => e == id).length;

  void _add(String id) {
    setState(() => _order.add(id));
  }

  void _remove(int index) {
    if (index < 0 || index >= _order.length) return;
    setState(() => _order.removeAt(index));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= _order.length) return;
    if (target < 0 || target >= _order.length) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
    });
  }

  void _clear() {
    setState(() => _order.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义顺延顺序'),
        actions: [
          if (_order.isNotEmpty)
            TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('清空'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child:  Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点击下方姓名标签添加成员；同一成员点多次表示一个周期内值多次班。序列顺序就是顺延顺序。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '顺延序列（${_order.length}）',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
               Text(
                '从上到下依次顺延',
                style: TextStyle(fontSize: 11, color: context.palette.textHint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_order.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child:  Center(
                child: Text(
                  '还没有序列，点击下方姓名标签添加',
                  style: TextStyle(fontSize: 12, color: context.palette.textHint),
                ),
              ),
            )
          else
            for (var i = 0; i < _order.length; i++) _buildOrderRow(i),
          const SizedBox(height: 20),
          const Text(
            '添加成员',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
           Text(
            '点一次加一个班次，可重复点击',
            style: TextStyle(fontSize: 11, color: context.palette.textHint),
          ),
          const SizedBox(height: 10),
          if (widget.members.isEmpty)
             Text(
              '还没有成员，请先返回“成员”页添加',
              style: TextStyle(fontSize: 13, color: context.palette.textHint),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.members.map(_buildMemberTag).toList(),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: FilledButton(
            onPressed:
 _order.isEmpty
                    ? null
                    : () =>
                        Navigator.of(context).pop(List<String>.from(_order)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('开始顺延'),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderRow(int index) {
    final member = _member(_order[index]);
    if (member == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              member.name.isEmpty ? '?' : member.name.characters.first,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              member.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '上移',
            onPressed: index == 0 ? null : () => _move(index, -1),
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '下移',
            onPressed:
 index == _order.length - 1 ? null : () => _move(index, 1),
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '删除',
            onPressed: () => _remove(index),
            icon: const Icon(Icons.close, size: 18, color: AppColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTag(ScheduleMember member) {
    final count = _countOf(member.id);
    return InkWell(
      onTap: () => _add(member.id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
 count > 0
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
 count > 0
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              member.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: count > 0 ? AppColors.primary : context.palette.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: count > 0 ? AppColors.primary : context.palette.surfaceVariant,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: count > 0 ? Colors.white : context.palette.textHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
