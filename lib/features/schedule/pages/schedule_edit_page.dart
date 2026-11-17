import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/schedule_api.dart';
import '../../../services/schedule_service.dart';
import '../models/schedule_models.dart';
import '../widgets/member_picker_sheet.dart';
import '../widgets/schedule_calendar.dart';
import 'schedule_rotation_order_page.dart';

class ScheduleEditPage extends StatefulWidget {
  const ScheduleEditPage({super.key});

  @override
  State<ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends State<ScheduleEditPage>
    with SingleTickerProviderStateMixin {
  final ScheduleService _service = ScheduleService.instance;
  final Random _random = Random();

  late final TabController _tabController;
  ScheduleData? _original;
  List<ScheduleMember> _members = [];
  Map<String, String> _assignments = {};
  List<String> _rotation = [];
  late DateTime _month;

  bool _loading = true;
  bool _dirty = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var schedule = _service.cachedSchedule;
      schedule ??= await _service.refresh(force: true);
      if (!_service.isAdmin) {
        setState(() {
          _loading = false;
          _error = '只有管理员可以编辑轮协表';
        });
        return;
      }
      if (schedule == null) {
        setState(() {
          _loading = false;
          _error = '轮协数据为空，请返回刷新后重试';
        });
        return;
      }
      final loaded = schedule;
      setState(() {
        _original = loaded;
        _members =
            loaded.members
                .map(
                  (m) => ScheduleMember(
                    id: m.id,
                    name: m.name,
                    active: m.active,
                    verified: m.verified,
                    lastSeenAt: m.lastSeenAt,
                    online: m.online,
                    seq: m.seq,
                  ),
                )
                .toList();
        _assignments = Map<String, String>.from(loaded.assignments);
        _rotation = List<String>.from(loaded.rotation);
        _dirty = false;
        _loading = false;
      });
      unawaited(_refreshMemberStatus());
    } on ScheduleAuthException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '管理员登录已失效，请返回重新验证';
      });
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '轮协数据加载失败，请返回重试';
      });
    }
  }

  /// 静默刷新成员在线状态，避免编辑页显示过期状态
  Future<void> _refreshMemberStatus() async {
    final updated = await _service.refresh(force: true, silent: true);
    if (!mounted || updated == null || _dirty) return;
    setState(() {
      for (final remote in updated.members) {
        final index = _members.indexWhere((m) => m.id == remote.id);
        if (index < 0) continue;
        final current = _members[index];
        _members[index] = ScheduleMember(
          id: current.id,
          name: current.name,
          active: current.active,
          verified: remote.verified,
          lastSeenAt: remote.lastSeenAt,
          online: remote.online,
          seq: current.seq,
        );
      }
    });
  }

  Future<void> _pickMemberForDate(DateTime date) async {
    final today = ScheduleDate.today();
    if (date.isBefore(today)) {
      _snack('过去的轮协记录不可编辑');
      return;
    }
    final key = ScheduleDate.key(date);
    final result = await showMemberPicker(
      context,
      members: _members,
      selectedId: _assignments[key],
      allowSwap: true,
      dateLabel:
          '${ScheduleDate.fullLabel(date)} ${ScheduleDate.weekday(date)}',
    );
    if (result == null) return;
    if (result.swap) {
      await _swapWithDate(date);
      return;
    }
    setState(() {
      if (result.clear) {
        _assignments.remove(key);
      } else if (result.memberId != null) {
        _assignments[key] = result.memberId!;
      }
      _dirty = true;
    });
  }

  String _memberName(String? id) {
    if (id == null) return '未安排';
    for (final member in _members) {
      if (member.id == id) return member.name;
    }
    return '未知成员';
  }

  Future<void> _swapWithDate(DateTime source) async {
    final today = ScheduleDate.today();
    if (source.isBefore(today)) {
      _snack('过去的轮协记录不可编辑');
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: source.isBefore(today) ? today : source,
      firstDate: today,
      lastDate: DateTime(2100),
      helpText: '选择要对调的日期',
    );
    if (picked == null || !mounted) return;
    final target = ScheduleDate.dayOnly(picked);
    if (ScheduleDate.isSameDay(target, source)) return;

    final sourceKey = ScheduleDate.key(source);
    final targetKey = ScheduleDate.key(target);
    final sourceMember = _assignments[sourceKey];
    final targetMember = _assignments[targetKey];
    if (sourceMember == null && targetMember == null) {
      _snack('这两天都没有安排，无需对调');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('对调轮协'),
            content: Text(
              '${ScheduleDate.fullLabel(source)}：${_memberName(sourceMember)}\n'
              '${ScheduleDate.fullLabel(target)}：${_memberName(targetMember)}\n\n'
              '确认交换这两天的协管人？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认对调'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      if (targetMember == null) {
        _assignments.remove(sourceKey);
      } else {
        _assignments[sourceKey] = targetMember;
      }
      if (sourceMember == null) {
        _assignments.remove(targetKey);
      } else {
        _assignments[targetKey] = sourceMember;
      }
      _dirty = true;
    });
    _snack(
      '已对调 ${ScheduleDate.shortLabel(source)} 和 ${ScheduleDate.shortLabel(target)}',
    );
  }

  Future<void> _addMember() async {
    final name = await _showNameDialog(title: '添加成员', confirmLabel: '添加');
    if (name == null) return;
    final id =
        'm_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1000)}';
    final nextSeq =
        _members.fold<int>(
          0,
          (value, member) =>
              (member.seq ?? 0) > value ? (member.seq ?? 0) : value,
        ) +
        1;
    setState(() {
      _members.add(ScheduleMember(id: id, name: name, seq: nextSeq));
      _dirty = true;
    });
  }

  Future<void> _editMember(ScheduleMember member) async {
    final name = await _showNameDialog(
      title: '修改姓名',
      confirmLabel: '保存',
      initial: member.name,
      excludeId: member.id,
    );
    if (name == null || name == member.name) return;
    final updated = member.copyWith(name: name);
    setState(() {
      final index = _members.indexWhere((m) => m.id == member.id);
      if (index >= 0) _members[index] = updated;
      _dirty = true;
    });
    if (member.id == _service.memberId) {
      await _service.selectMember(updated);
    }
  }

  Future<void> _deleteMember(ScheduleMember member) async {
    final pastCount = _pastDutyCount(member.id);
    if (pastCount > 0) {
      _snack('“${member.name}”有 $pastCount 天历史轮协记录，不能删除；可改名保留');
      return;
    }
    final futureCount = _futureDutyCount(member.id);
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('删除成员'),
            content: Text(
              futureCount > 0
                  ? '“${member.name}”还有 $futureCount 个未来协管日，删除后这些日期将变为空缺。'
                  : '确定删除“${member.name}”吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    setState(() {
      _members.removeWhere((m) => m.id == member.id);
      _assignments.removeWhere((_, memberId) => memberId == member.id);
      _rotation.removeWhere((id) => id == member.id);
      _dirty = true;
    });
  }

  Future<String?> _showNameDialog({
    required String title,
    required String confirmLabel,
    String? initial,
    String? excludeId,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              void submit() {
                final name = controller.text.trim();
                String? error;
                if (name.isEmpty) {
                  error = '请输入姓名';
                } else if (name.length > 30) {
                  error = '姓名不能超过 30 个字';
                } else if (_members.any(
                  (m) =>
                      m.id != excludeId &&
                      m.name.toLowerCase() == name.toLowerCase(),
                )) {
                  error = '这个姓名已经存在';
                }
                if (error != null) {
                  setDialogState(() => errorText = error);
                  return;
                }
                Navigator.pop(ctx, name);
              }

              return AlertDialog(
                title: Text(title),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: '请输入成员姓名',
                    errorText: errorText,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  FilledButton(onPressed: submit, child: Text(confirmLabel)),
                ],
              );
            },
          ),
    );
    controller.dispose();
    return result;
  }

  int _futureDutyCount(String memberId) {
    final today = ScheduleDate.today();
    return _assignments.entries.where((entry) {
      if (entry.value != memberId) return false;
      final date = ScheduleDate.tryParseKey(entry.key);
      return date != null && !date.isBefore(today);
    }).length;
  }

  int _totalDutyCount(String memberId) =>
      _assignments.values.where((id) => id == memberId).length;

  int _pastDutyCount(String memberId) {
    final today = ScheduleDate.today();
    return _assignments.entries.where((entry) {
      if (entry.value != memberId) return false;
      final date = ScheduleDate.tryParseKey(entry.key);
      return date != null && date.isBefore(today);
    }).length;
  }

  int _changedDateCount() {
    final old = _original?.assignments ?? const <String, String>{};
    final keys = {...old.keys, ..._assignments.keys};
    var count = 0;
    for (final key in keys) {
      if (old[key] != _assignments[key]) count++;
    }
    return count;
  }

  Future<void> _submit() async {
    if (_original == null) return;
    if (_members.isEmpty) {
      _snack('至少保留一个成员');
      return;
    }

    final changedDates = _changedDateCount();
    final oldIds = _original!.members.map((m) => m.id).toSet();
    final newIds = _members.map((m) => m.id).toSet();
    final added = newIds.difference(oldIds).length;
    final removed = oldIds.difference(newIds).length;
    final renamed =
        _members.where((m) {
          final old = _original!.memberById(m.id);
          return old != null && old.name != m.name;
        }).length;
    final rotationChanged = !listEquals(_rotation, _original!.rotation);

    if (changedDates == 0 &&
        added == 0 &&
        removed == 0 &&
        renamed == 0 &&
        !rotationChanged) {
      _snack('没有需要提交的修改');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('提交轮协表'),
            content: Text(
              '本次修改：轮协 $changedDates 天'
              '${added > 0 ? '，新增成员 $added 人' : ''}'
              '${removed > 0 ? '，删除成员 $removed 人' : ''}'
              '${renamed > 0 ? '，改名 $renamed 人' : ''}'
              '${rotationChanged ? '，顺延序列已更新' : ''}。\n\n'
              '提交后会写入私有仓库并同步给所有成员；协管日期变化的人会收到变更通知。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('提交'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    final edited = _original!.copyWith(
      members: List<ScheduleMember>.unmodifiable(_members),
      assignments: Map<String, String>.unmodifiable(_assignments),
      rotation:
          _rotation.where((id) => _members.any((m) => m.id == id)).toList(),
    );
    await _doSubmit(edited);
  }

  Future<void> _doSubmit(
    ScheduleData edited, {
    int? baseRevisionOverride,
  }) async {
    setState(() => _submitting = true);
    try {
      final result = await _service.submit(
        edited,
        baseRevisionOverride: baseRevisionOverride,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _dirty = false;
      });
      await _showSubmitSuccess(result);
      if (mounted) Navigator.of(context).pop(true);
    } on ScheduleConflictException catch (conflict) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final action = await showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('轮协已被更新'),
              content: Text(
                '其他设备已经提交了新的轮协版本（当前版本 ${conflict.currentRevision}）。\n\n'
                '你可以用当前编辑覆盖远程版本，或放弃修改并刷新最新数据。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'refresh'),
                  child: const Text('放弃并刷新'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'overwrite'),
                  child: const Text('用我的版本覆盖'),
                ),
              ],
            ),
      );
      if (!mounted) return;
      if (action == 'overwrite') {
        await _doSubmit(edited, baseRevisionOverride: conflict.currentRevision);
      } else if (action == 'refresh') {
        try {
          await _service.refresh(force: true);
          await _load();
          _snack('已加载最新轮协');
        } catch (e) {
          _snack('刷新失败，请返回重试');
        }
      }
    } on ScheduleAuthException {
      if (!mounted) return;
      setState(() => _submitting = false);
      final go = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('管理员登录已失效'),
              content: const Text('请重新输入管理密钥后再编辑轮协。'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去验证'),
                ),
              ],
            ),
      );
      if (go == true && mounted) {
        context.pushReplacement('/schedule');
      }
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('提交失败，请检查网络后重试');
    }
  }

  Future<void> _showSubmitSuccess(ScheduleSubmitResult result) async {
    final changed = result.changedMemberIds.length;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: 8),
                Text('提交成功'),
              ],
            ),
            content: Text(
              '已写入私有仓库，当前版本 ${result.schedule.revision}。'
              '${changed > 0 ? '\n\n$changed 名成员的轮协有变化，他们下次联网时会收到变更通知。' : ''}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('放弃修改？'),
            content: const Text('当前有未提交的轮协修改，离开后这些修改会丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
    );
    return result == true;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmDiscard();
        if (leave) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('编辑轮协表'),
          actions: [
            if (_submitting)
              const Padding(
                padding: EdgeInsets.only(right: 18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              TextButton.icon(
                onPressed: _dirty ? _submit : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('提交'),
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [Tab(text: '轮协'), Tab(text: '成员')],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 56,
                color: AppColors.textDisabled,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [_buildScheduleTab(), _buildMembersTab()],
    );
  }

  Widget _buildScheduleTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.touch_app_outlined, size: 18, color: AppColors.info),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '点击日期选择当天负责人。一天只能安排一人，未选择的日期显示为未轮协。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildRotationActions(),
        const SizedBox(height: 14),
        ScheduleCalendar(
          month: _month,
          assignments: _assignments,
          members: _members,
          myMemberId: _service.memberId,
          editable: true,
          allowPastTap: false,
          onPreviousMonth: (m) => setState(() => _month = m),
          onNextMonth: (m) => setState(() => _month = m),
          onToday: () {
            final now = DateTime.now();
            setState(() => _month = DateTime(now.year, now.month, 1));
          },
          onDayTap: _pickMemberForDate,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: AppColors.textHint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '当前共 ${_members.length} 名成员，已安排 ${_assignments.length} 天',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRotationActions() {
    final count = _rotation.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '顺延轮协',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (count > 0)
              Text(
                '当前序列 $count 个班次',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _rotationButton(
          icon: Icons.format_list_numbered,
          title: '按 ID 顺序顺延',
          subtitle: '按成员编号顺序循环填充',
          onTap: () => _openBatchRotation(custom: false),
        ),
        const SizedBox(height: 8),
        _rotationButton(
          icon: Icons.tune,
          title: '自定义顺序顺延',
          subtitle: count > 0 ? '当前序列 $count 个班次' : '自己设置成员顺序和每人班次数',
          onTap: () => _openBatchRotation(custom: true),
        ),
      ],
    );
  }

  Widget _rotationButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.textDisabled,
          ),
        ],
      ),
    );
  }

  List<ScheduleMember> _idOrderMembers() {
    final list = _members.toList();
    list.sort((a, b) {
      final sa = a.seq ?? 0;
      final sb = b.seq ?? 0;
      if (sa > 0 && sb > 0 && sa != sb) return sa.compareTo(sb);
      if (sa > 0 && sb <= 0) return -1;
      if (sa <= 0 && sb > 0) return 1;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Future<void> _openBatchRotation({required bool custom}) async {
    List<String> sequence;
    if (custom) {
      final result = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder:
              (_) => ScheduleRotationOrderPage(
                members: _members,
                initial: _rotation,
              ),
        ),
      );
      if (!mounted || result == null) return;
      sequence = result;
      if (!listEquals(_rotation, sequence)) {
        setState(() {
          _rotation = List<String>.from(sequence);
          _dirty = true;
        });
      }
    } else {
      sequence = _idOrderMembers().map((m) => m.id).toList();
    }
    if (sequence.isEmpty) {
      _snack('请先在“成员”页添加成员');
      return;
    }

    final today = ScheduleDate.today();
    final monthStart = DateTime(_month.year, _month.month, 1);
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    if (monthEnd.isBefore(today)) {
      _snack('过去的月份不可编辑');
      return;
    }
    var start = monthStart.isBefore(today) ? today : monthStart;
    var end = monthEnd;
    var overwrite = false;
    String? rangeError;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              Future<void> pickDate({required bool isStart}) async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: isStart ? start : end,
                  firstDate: today,
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                setDialogState(() {
                  if (isStart) {
                    start = picked;
                  } else {
                    end = picked;
                  }
                  rangeError = null;
                });
              }

              return AlertDialog(
                title: Text(custom ? '按自定义顺序顺延' : '按 ID 顺序顺延'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dateField(
                        label: '开始日期',
                        date: start,
                        onTap: () => pickDate(isStart: true),
                      ),
                      const SizedBox(height: 8),
                      _dateField(
                        label: '结束日期',
                        date: end,
                        onTap: () => pickDate(isStart: false),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '覆盖区间内已有轮协',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: overwrite,
                        onChanged:
                            (value) => setDialogState(() => overwrite = value),
                      ),
                      const Text(
                        '顺延会按区间内每一天推进；不覆盖时只填空缺日期，但顺序仍会前进。',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: AppColors.textHint,
                        ),
                      ),
                      if (rangeError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          rangeError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (start.isBefore(today)) {
                        setDialogState(() => rangeError = '开始日期不能早于今天');
                        return;
                      }
                      if (end.isBefore(today)) {
                        setDialogState(() => rangeError = '结束日期不能早于今天');
                        return;
                      }
                      final days = ScheduleDate.daysBetween(start, end) + 1;
                      if (days < 1) {
                        setDialogState(() => rangeError = '结束日期不能早于开始日期');
                        return;
                      }
                      if (days > 366) {
                        setDialogState(() => rangeError = '一次最多顺延 366 天');
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('应用顺延'),
                  ),
                ],
              );
            },
          ),
    );
    if (ok != true || !mounted) return;

    var assigned = 0;
    var index = 0;
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final key = ScheduleDate.key(day);
      if (overwrite || !_assignments.containsKey(key)) {
        _assignments[key] = sequence[index % sequence.length];
        assigned++;
      }
      index++;
    }
    if (assigned == 0) {
      _snack('区间内没有可填充的日期');
      return;
    }
    setState(() {
      _rotation = List<String>.from(sequence);
      _dirty = true;
    });
    _snack('已按顺延填充 $assigned 天');
  }

  Widget _dateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(ScheduleDate.fullLabel(date)),
      ),
    );
  }

  Widget _buildMembersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Row(
          children: [
            Text(
              '成员（${_members.length}）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _addMember,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('添加成员'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 2),
          child: Text(
            '姓名会显示在轮协表上；重名请加区分，例如“张三 A”。',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ),
        const SizedBox(height: 12),
        if (_members.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.group_add_outlined,
                  size: 48,
                  color: AppColors.textDisabled,
                ),
                const SizedBox(height: 10),
                const Text(
                  '还没有成员',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '先添加成员，再到“轮协”页安排日期',
                  style: TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.add),
                  label: const Text('添加第一个成员'),
                ),
              ],
            ),
          )
        else
          ..._members.map((member) {
            final future = _futureDutyCount(member.id);
            final total = _totalDutyCount(member.id);
            final isMe = member.id == _service.memberId;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    member.name.isEmpty ? '?' : member.name.characters.first,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '我',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    if (!member.verified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textHint.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '未验证',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (member.online
                                  ? AppColors.success
                                  : AppColors.textHint)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color:
                                    member.online
                                        ? AppColors.success
                                        : AppColors.textHint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              member.online ? '在线' : '离线',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color:
                                    member.online
                                        ? AppColors.success
                                        : AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  '${member.seq ?? '-'}号 · 未来 $future 天 · 累计 $total 天',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '修改姓名',
                      onPressed: () => _editMember(member),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: '删除成员',
                      onPressed: () => _deleteMember(member),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
