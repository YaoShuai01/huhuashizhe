import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../core/theme/app_theme.dart';
import '../../../services/schedule_api.dart';
import '../../../services/schedule_message_service.dart';
import '../../../services/schedule_notification_service.dart';
import '../../../services/schedule_service.dart';
import '../models/schedule_models.dart';
import '../widgets/schedule_calendar.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with WidgetsBindingObserver {
  final ScheduleService _service = ScheduleService.instance;
  final ScheduleNotificationService _notify =
      ScheduleNotificationService.instance;
  final ScheduleMessageService _messages = ScheduleMessageService.instance;

  ScheduleData? _schedule;
  late DateTime _month;
  bool _loading = false;
  bool _authDialogShown = false;
  String? _error;
  String? _lastShownChange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _schedule = _service.cachedSchedule;
    _service.changeNotifier.addListener(_onChange);
    _messages.unreadNotifier.addListener(_onUnreadChange);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(force: true);
      _syncMessages();
    });
  }

  @override
  void dispose() {
    _service.changeNotifier.removeListener(_onChange);
    _messages.unreadNotifier.removeListener(_onUnreadChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onUnreadChange() {
    if (mounted) setState(() {});
  }

  Future<void> _syncMessages() async {
    await _messages.init();
    await _messages.refresh(silent: true);
  }

  Future<void> _openMessages() async {
    await context.push('/schedule/messages');
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _schedule = _service.cachedSchedule);
      unawaited(
        _notify.refreshPermissionStatus().then((_) {
          if (mounted) setState(() {});
        }),
      );
      unawaited(_syncMessages());
    }
  }

  void _onChange() {
    final message = _service.changeNotifier.value;
    if (!mounted ||
        message == null ||
        message.isEmpty ||
        message == _lastShownChange) {
      return;
    }
    _lastShownChange = message;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '知道了',
          onPressed: () {
            _service.clearPendingChangeMessage();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _refresh({bool force = false}) async {
    if (!_service.isAuthenticated) {
      _redirectToGate();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedule = await _service.refresh(force: force);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } on ScheduleAuthException {
      if (!mounted) return;
      setState(() => _loading = false);
      await _showAuthExpired();
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
        _error = '同步失败，请稍后重试';
      });
    }
  }

  void _redirectToGate() {
    if (!mounted) return;
    context.pushReplacement('/schedule');
  }

  Future<void> _showAuthExpired() async {
    if (_authDialogShown) return;
    _authDialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('登录已失效'),
            content: const Text('轮协登录状态已失效，请重新输入轮协密钥。'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('去验证'),
              ),
            ],
          ),
    );
    _authDialogShown = false;
    if (mounted) _redirectToGate();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('退出轮协'),
            content: const Text('将清除本机的轮协登录状态和姓名绑定，下次需要重新输入轮协密钥。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('退出'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    await _service.logout();
    if (!mounted) return;
    _redirectToGate();
  }

  Future<void> _showNotificationHelp() async {
    final granted = await _notify.requestPermissions();
    await _service.rescheduleNotifications();
    if (!mounted) return;
    setState(() {});
    if (!granted) {
      final go = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('通知权限未开启'),
              content: const Text(
                '请在系统设置中允许“护花使者”发送通知，并关闭省电限制，否则协管前一天 17:00 可能收不到提醒。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('稍后'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去设置'),
                ),
              ],
            ),
      );
      if (go == true) {
        await ph.openAppSettings();
      }
    }
  }

  Future<void> _openEdit() async {
    final changed = await context.push<bool>('/schedule/edit');
    if (changed == true && mounted) {
      setState(() => _schedule = _service.cachedSchedule);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('轮协表已更新')));
    }
  }

  void _showDayDetail(DateTime date) {
    final schedule = _schedule;
    if (schedule == null) return;
    final key = ScheduleDate.key(date);
    final memberId = schedule.assignments[key];
    final member = schedule.memberById(memberId);
    final isMine = memberId != null && memberId == _service.memberId;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ScheduleDate.fullLabel(date),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ScheduleDate.weekday(date),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            isMine
                                ? scheme.primary
                                : scheme.primary.withValues(alpha: 0.1),
                        child: Text(
                          member == null
                              ? '—'
                              : (member.name.isEmpty
                                  ? '?'
                                  : member.name.characters.first),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: isMine ? scheme.onPrimary : scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member?.name ?? '未轮协',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isMine
                                  ? '这是你的协管日'
                                  : (member == null ? '这一天还没有安排负责人' : '协管负责人'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isMine)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '我',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_service.isAdmin) ...[
                    const SizedBox(height: 22),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openEdit();
                      },
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: const Text('去编辑轮协表'),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('轮协管理'),
        bottom:
            _loading
                ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
                : null,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => _refresh(force: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _openEdit();
                  break;
                case 'notifications':
                  _showNotificationHelp();
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  if (_service.isAdmin)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_calendar),
                        title: Text('编辑轮协'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'notifications',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.notifications_none),
                      title: Text('通知设置'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout),
                      title: Text('退出轮协'),
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: schedule == null ? _buildEmpty() : _buildContent(schedule),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有轮协数据',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击刷新重试；如果轮协表还是空的，请管理员先添加成员和日期。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _refresh(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
            if (_service.isAdmin) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openEdit,
                icon: const Icon(Icons.edit_calendar),
                label: const Text('去添加成员和轮协'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScheduleData schedule) {
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ..._buildBanners(schedule),
          _buildMyDutyCard(schedule),
          const SizedBox(height: 18),
          _sectionTitle('全部成员轮协表'),
          const SizedBox(height: 8),
          ScheduleCalendar(
            month: _month,
            assignments: schedule.assignments,
            members: schedule.members,
            myMemberId: _service.memberId,
            onPreviousMonth: (m) => setState(() => _month = m),
            onNextMonth: (m) => setState(() => _month = m),
            onToday: () {
              final now = DateTime.now();
              setState(() => _month = DateTime(now.year, now.month, 1));
            },
            onDayTap: _showDayDetail,
          ),
          const SizedBox(height: 18),
          _buildUpcomingSection(schedule),
        ],
      ),
    );
  }

  List<Widget> _buildBanners(ScheduleData schedule) {
    final banners = <Widget>[];
    final pending = _service.pendingChangeMessage;
    if (pending != null && pending.isNotEmpty) {
      banners.add(
        _banner(
          icon: Icons.campaign_outlined,
          color: AppColors.info,
          text: pending,
          actionLabel: '知道了',
          onAction: () {
            _service.clearPendingChangeMessage();
            setState(() {});
          },
        ),
      );
    }

    if (_service.lastSyncFailed) {
      banners.add(
        _banner(
          icon: Icons.wifi_off_rounded,
          color: AppColors.textSecondary,
          text: '离线：当前显示上次同步的数据',
          actionLabel: '重试',
          onAction: () => _refresh(force: true),
        ),
      );
    }

    if (_error != null) {
      banners.add(
        _banner(
          icon: Icons.error_outline,
          color: AppColors.error,
          text: _error!,
          actionLabel: '重试',
          onAction: () => _refresh(force: true),
        ),
      );
    }

    if (banners.isEmpty) return const [];
    return [
      for (var i = 0; i < banners.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        banners[i],
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: color,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMyDutyCard(ScheduleData schedule) {
    final memberId = _service.memberId;
    final member = memberId == null ? null : schedule.memberById(memberId);
    if (member == null) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.person_off_outlined, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _service.hasMemberIdentity ? '你已不在最新轮协名单中' : '还没有绑定你的姓名',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '请联系管理员更新轮协表',
                      style: TextStyle(fontSize: 12, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final today = ScheduleDate.today();
    final onDutyToday = schedule.isMemberOnDuty(member.id, today);
    final upcoming = schedule.upcomingDatesForMember(member.id);
    final next = upcoming.isNotEmpty ? upcoming.first : null;
    final days = next == null ? null : ScheduleDate.daysBetween(today, next);
    final bigText = onDutyToday ? '今天你协管' : (next == null ? '暂无轮协' : '下次协管');
    final subtitle =
        onDutyToday
            ? '${ScheduleDate.fullLabel(today)} ${ScheduleDate.weekday(today)}'
            : (next == null
                ? '当前没有未来的协管安排'
                : '${ScheduleDate.fullLabel(next)} ${ScheduleDate.weekday(next)}');
    final badge =
        onDutyToday
            ? '今天'
            : (days == null
                ? ''
                : days == 0
                ? '今天'
                : days == 1
                ? '明天'
                : '还有 $days 天');

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, color: Colors.white, size: 22),
              const SizedBox(width: 7),
              const Text(
                '我的协管',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  member.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  bigText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (badge.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _buildMessageEntry(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
            ),
          ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  upcoming.take(2).map((date) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ScheduleDate.shortWithWeekday(date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageEntry() {
    final unread = _messages.unread;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openMessages,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              const Text(
                '留言池',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingSection(ScheduleData schedule) {
    final memberId = _service.memberId;
    if (memberId == null || memberId.isEmpty) return const SizedBox.shrink();
    final upcoming = schedule.upcomingDatesForMember(memberId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('我的协管日期'),
            const Spacer(),
            Text(
              '共 ${upcoming.length} 天',
              style: const TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              '暂无未来协管安排',
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                upcoming.take(12).map((date) {
                  return Chip(
                    avatar: const Icon(Icons.event, size: 15),
                    label: Text(
                      ScheduleDate.shortWithWeekday(date),
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.5),
                    ),
                  );
                }).toList(),
          ),
        if (upcoming.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '还有 ${upcoming.length - 12} 天，请在月历中查看',
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
