import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/schedule_models.dart';

class MemberPickResult {
  final String? memberId;
  final bool clear;
  final bool swap;

  const MemberPickResult({
    this.memberId,
    this.clear = false,
    this.swap = false,
  });
}

Future<MemberPickResult?> showMemberPicker(
  BuildContext context, {
  required List<ScheduleMember> members,
  String? selectedId,
  bool allowClear = true,
  bool allowSwap = false,
  String? dateLabel,
}) {
  return showModalBottomSheet<MemberPickResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _MemberPickerSheet(
      members: members,
      selectedId: selectedId,
      allowClear: allowClear,
      allowSwap: allowSwap,
      dateLabel: dateLabel,
    ),
  );
}

class _MemberPickerSheet extends StatefulWidget {
  final List<ScheduleMember> members;
  final String? selectedId;
  final bool allowClear;
  final bool allowSwap;
  final String? dateLabel;

  const _MemberPickerSheet({
    required this.members,
    this.selectedId,
    this.allowClear = true,
    this.allowSwap = false,
    this.dateLabel,
  });

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members.where((m) {
      if (_keyword.isEmpty) return true;
      return m.name.toLowerCase().contains(_keyword.toLowerCase());
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '选择协管成员',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        if (widget.dateLabel != null)
                          Text(
                            widget.dateLabel!,
                            style:  TextStyle(
                              fontSize: 12,
                              color: context.palette.textHint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                onChanged: (v) => setState(() => _keyword = v.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索姓名',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.allowSwap)
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: AppColors.info),
                title: const Text('对调轮协'),
                subtitle: const Text('与另一个日期交换协管人'),
                onTap: () => Navigator.pop(
                  context,
                  const MemberPickResult(swap: true),
                ),
              ),
            if (widget.allowClear)
              ListTile(
                leading: const Icon(Icons.event_busy, color: AppColors.warning),
                title: const Text('清空该日'),
                subtitle: const Text('该日期变为未轮协'),
                onTap: () => Navigator.pop(
                  context,
                  const MemberPickResult(clear: true),
                ),
              ),
            const Divider(),
            Expanded(
              child: members.isEmpty
                  ? Center(
                      child: Text(
                        widget.members.isEmpty
                            ? '还没有成员，请先在“成员”页添加'
                            : '没有匹配的成员',
                        style:  TextStyle(color: context.palette.textHint),
                      ),
                    )
                  : ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final selected = member.id == widget.selectedId;
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
 Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              member.name.isEmpty ? '?' : member.name.characters.first,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            member.name,
                            style: TextStyle(
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            MemberPickResult(memberId: member.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
