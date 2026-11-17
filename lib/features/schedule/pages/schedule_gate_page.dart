import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/schedule_api.dart';
import '../../../services/schedule_service.dart';
import '../models/schedule_models.dart';
import 'schedule_ceremony_page.dart';

enum _GatePhase { loading, key, name, config, offline }

class ScheduleGatePage extends StatefulWidget {
  const ScheduleGatePage({super.key});

  @override
  State<ScheduleGatePage> createState() => _ScheduleGatePageState();
}

class _ScheduleGatePageState extends State<ScheduleGatePage> {
  final ScheduleService _service = ScheduleService.instance;
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  _GatePhase _phase = _GatePhase.loading;
  String? _error;
  String? _keyError;
  bool _authLoading = false;
  ScheduleData? _schedule;
  String? _nameError;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _phase = _GatePhase.loading;
      _error = null;
    });
    await _service.init();
    final configured = await _service.isServiceConfigured();
    if (!mounted) return;
    if (!configured) {
      setState(() => _phase = _GatePhase.config);
      return;
    }
    if (!_service.isAuthenticated) {
      setState(() => _phase = _GatePhase.key);
      return;
    }
    await _enterWithSession();
  }

  Future<void> _enterWithSession() async {
    setState(() => _phase = _GatePhase.loading);
    try {
      final schedule = await _service.refresh(force: true);
      if (!mounted) return;
      if (schedule == null) {
        setState(() {
          _phase = _GatePhase.key;
          _keyError = '登录已失效，请重新输入轮协密钥';
        });
        return;
      }
      _schedule = schedule;
      if (_service.hasMemberIdentity) {
        final member = schedule.memberById(_service.memberId);
        if (member != null) {
          _goToSchedule();
          return;
        }
      }
      setState(() {
        _phase = _GatePhase.name;
        _error =
            _service.hasMemberIdentity ? '你之前的姓名已不在最新轮协表中，请重新选择或联系管理员' : null;
      });
    } on ScheduleAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _GatePhase.key;
        _keyError = e.message;
      });
    } on ScheduleNotConfiguredException {
      if (!mounted) return;
      setState(() => _phase = _GatePhase.config);
    } on ScheduleApiException {
      if (!mounted) return;
      final cached = _service.cachedSchedule;
      if (cached != null && _service.hasMemberIdentity) {
        _schedule = cached;
        _goToSchedule();
        return;
      }
      setState(() {
        _phase = _GatePhase.offline;
        _error = '服务器未启动，请联系管理员';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _GatePhase.offline;
        _error = '服务器未启动，请联系管理员';
      });
    }
  }

  Future<void> _submitKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _keyError = '请输入轮协密钥');
      return;
    }
    setState(() {
      _authLoading = true;
      _keyError = null;
    });
    try {
      await _service.authenticate(key);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      final schedule = await _service.refresh(force: true);
      if (!mounted) return;
      _schedule = schedule;
      if (_service.hasMemberIdentity) {
        final member = schedule?.memberById(_service.memberId);
        if (member != null) {
          _goToSchedule();
          return;
        }
      }
      setState(() {
        _phase = _GatePhase.name;
        _nameError = null;
        _error = null;
      });
    } on ScheduleAuthException catch (e) {
      if (!mounted) return;
      setState(() => _keyError = e.message);
    } on ScheduleNetworkException {
      if (!mounted) return;
      setState(() {
        _phase = _GatePhase.offline;
        _error = '服务器未启动，请联系管理员';
      });
    } on ScheduleApiException catch (e) {
      if (!mounted) return;
      setState(() => _keyError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _keyError = '服务器未启动，请联系管理员');
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _verifyName() async {
    final schedule = _schedule;
    if (schedule == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请输入姓名');
      return;
    }
    ScheduleMember? matched;
    for (final member in schedule.activeMembers) {
      if (member.name.toLowerCase() == name.toLowerCase()) {
        matched = member;
        break;
      }
    }
    if (matched == null) {
      setState(() => _nameError = '姓名验证失败，请重新输入');
      return;
    }

    final member = matched;
    setState(() {
      _verifying = true;
      _nameError = null;
    });
    await _service.selectMember(member);
    if (!mounted) return;
    setState(() => _verifying = false);

    final index = schedule.members.indexOf(member) + 1;
    final seq = member.seq;
    final number = (seq != null && seq > 0) ? seq : (index > 0 ? index : 1);
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder:
            (_, __, ___) => ScheduleCeremonyPage(
              memberNumber: number,
              memberName: member.name,
            ),
        transitionsBuilder:
            (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted) return;

    await _service.rescheduleNotifications();
    if (!mounted) return;
    _goToSchedule();
  }

  Future<void> _openSetupEditor() async {
    if (!_service.isAdmin) return;
    await context.push<bool>('/schedule/edit');
    if (!mounted) return;
    try {
      final schedule = await _service.refresh(force: true);
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _phase = _GatePhase.name;
        _nameError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _GatePhase.name;
        _nameError = '轮协数据刷新失败，请重试';
      });
    }
  }

  void _goToSchedule() {
    if (!mounted) return;
    context.pushReplacement('/schedule/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('轮协管理')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _GatePhase.loading:
        return _buildLoading();
      case _GatePhase.key:
        return _buildKeyEntry();
      case _GatePhase.name:
        return _buildNameSelection();
      case _GatePhase.config:
        return _buildConfigError();
      case _GatePhase.offline:
        return _buildOffline();
    }
  }

  Widget _buildLoading() {
    return const Center(
      key: ValueKey('loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在验证轮协身份...', style: TextStyle(color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildKeyEntry() {
    return SingleChildScrollView(
      key: const ValueKey('key'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '团队轮协',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            '请输入轮协密钥',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _keyController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 10,
              fontWeight: FontWeight.w700,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '••••••',
              counterText: '',
              contentPadding: EdgeInsets.symmetric(vertical: 18),
            ),
            onSubmitted: (_) => _submitKey(),
          ),
          if (_keyError != null) ...[
            const SizedBox(height: 10),
            Text(
              _keyError!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _authLoading ? null : _submitKey,
            child:
                _authLoading
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Text('进入轮协管理'),
          ),
          const SizedBox(height: 18),
          const Text(
            '输入密钥并验证姓名后进入；有编辑权限的密钥会多一个编辑入口。\n密钥仅用于团队内部轮协，请勿外传。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textHint,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          TextButton.icon(
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新检查服务'),
          ),
        ],
      ),
    );
  }

  Widget _buildNameSelection() {
    final schedule = _schedule;
    final isEmpty = schedule == null || schedule.activeMembers.isEmpty;

    return SingleChildScrollView(
      key: const ValueKey('name'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '验证姓名',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '密钥已验证，输入本人姓名即可进入；下次无需重新输入密钥',
                      style: TextStyle(fontSize: 12, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (isEmpty) ...[
            const Icon(
              Icons.group_off_outlined,
              size: 56,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 12),
            Text(
              _service.isAdmin
                  ? '轮协表还没有成员\n先添加成员和你自己的姓名，再回来验证；第一个添加的成员为1号'
                  : '管理员还没有录入成员\n请联系管理员添加后再进入',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint, height: 1.6),
            ),
            if (_service.isAdmin) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: _openSetupEditor,
                child: const Text('去添加成员'),
              ),
            ],
          ] else ...[
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '请输入本人姓名',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              onSubmitted: (_) => _verifyName(),
            ),
            if (_nameError != null) ...[
              const SizedBox(height: 10),
              Text(
                _nameError!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _verifying ? null : _verifyName,
              child:
                  _verifying
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('验证并进入'),
            ),
            if (_service.isAdmin) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _openSetupEditor,
                child: const Text('管理成员'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildConfigError() {
    return Center(
      key: const ValueKey('config'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              '轮协服务未配置',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '管理员需要先部署轮协 Worker，并在 config/schedule.json 中填写服务地址。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffline() {
    return Center(
      key: const ValueKey('offline'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              '服务器未启动',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '请检查网络后重试',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '密钥已验证，无需重新输入',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _enterWithSession,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed:
                  () => setState(() {
                    _phase = _GatePhase.key;
                    _keyError = null;
                  }),
              child: const Text('更换密钥'),
            ),
          ],
        ),
      ),
    );
  }
}
