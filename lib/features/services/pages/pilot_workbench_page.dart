import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';
import 'pilot_profile_page.dart';

/// 飞手工作台：查看附近订单并接单
class PilotWorkbenchPage extends StatefulWidget {
  const PilotWorkbenchPage({super.key});

  @override
  State<PilotWorkbenchPage> createState() => _PilotWorkbenchPageState();
}

class _PilotWorkbenchPageState extends State<PilotWorkbenchPage> {
  static const List<_FarmOrder> _seedOrders = [
    _FarmOrder(
      crop: '油菜',
      area: 60,
      village: '监利市新沟镇',
      time: '明天上午',
      price: 480,
    ),
    _FarmOrder(
      crop: '水稻',
      area: 120,
      village: '洪湖市峰口镇',
      time: '11月22日下午',
      price: 960,
    ),
    _FarmOrder(
      crop: '小麦',
      area: 45,
      village: '江陵县白马镇',
      time: '11月23日上午',
      price: 360,
    ),
  ];

  bool _accepting = true;

  // 接单状态保存在页面外的存储中，退出工作台再进入不会丢失
  final List<_FarmOrder> _pending = _PilotOrders.pending;
  final List<_AcceptedOrder> _accepted = _PilotOrders.accepted;

  Future<void> _accept(_FarmOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AcceptOrderDialog(order: order),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _pending.remove(order);
      _accepted.insert(0, _AcceptedOrder(order: order, acceptedAt: DateTime.now()));
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已接单，请尽快联系农户确认作业时间')),
      );
  }

  Future<void> _cancelAccepted(_AcceptedOrder entry) async {
    final elapsed = DateTime.now().difference(entry.acceptedAt);
    final charged = elapsed.inHours >= 12;
    final fee = entry.order.price * 0.02;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消订单'),
        content: Text(
          charged
              ? '接单已超过 12 小时，取消后需向农户支付订单金额 2% 的接单费用（约 ￥${fee.toStringAsFixed(0)}）。确认取消吗？'
              : '接单未满 12 小时，可免费取消。确认取消吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _accepted.remove(entry);
      _pending.insert(0, entry.order);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            charged
                ? '已取消订单，将向农户支付 ￥${fee.toStringAsFixed(0)} 接单费用'
                : '已取消订单',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('飞手工作台')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              value: _accepting,
              onChanged: (value) => setState(() => _accepting = value),
              activeColor: AppColors.primary,
              title: const Text(
                '接受新订单',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: const Text(
                '关闭后不再展示新的农户订单',
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _profileCard(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statCard('待接订单', '${_pending.length} 单'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard('已接订单', '${_accepted.length} 单'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '附近订单',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_pending.isEmpty)
            _emptyCard('暂无待接订单，稍后再来看看')
          else
            for (final order in _pending) _orderCard(order),
          const SizedBox(height: 20),
          const Text(
            '我的接单',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_accepted.isEmpty)
            _emptyCard('还没有接单，接单后会展示在这里')
          else
            for (final entry in _accepted) _acceptedCard(entry),
        ],
      ),
    );
  }

  Widget _profileCard() {
    final profile = PilotProfileStore.current;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
        title: const Text(
          '飞手资料',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          profile == null
              ? '完善姓名、服务区域与报价，让更多农户找到你'
              : '已完善：${profile.name} · ${profile.region}',
          style: const TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
        onTap: () async {
          await context.push('/services/booking/pilot/profile');
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.textHint),
          ),
        ),
      ),
    );
  }

  Widget _orderCard(_FarmOrder order) {
    return ElderCareBlock(
      readText:
          '${order.crop}${order.area.toStringAsFixed(0)}亩，${order.village}，${order.time}，预估${order.price.toStringAsFixed(0)}元',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${order.crop} · ${order.area.toStringAsFixed(0)} 亩',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '￥${order.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow(Icons.place_outlined, order.village),
              const SizedBox(height: 4),
              _infoRow(Icons.schedule, order.time),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _accepting ? () => _accept(order) : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(96, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle:
                        Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                  child: const Text('接单'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _acceptedCard(_AcceptedOrder entry) {
    final order = entry.order;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order.crop} · ${order.area.toStringAsFixed(0)} 亩',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.village} · ${order.time}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '已接单',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _cancelAccepted(entry),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '取消订单',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textHint),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 飞手接单状态：页面退出后仍保留，再次进入工作台可看到已接订单
class _PilotOrders {
  static final List<_FarmOrder> pending =
      List.of(_PilotWorkbenchPageState._seedOrders);
  static final List<_AcceptedOrder> accepted = <_AcceptedOrder>[];
}

/// 已接订单，记录接单时间用于判断取消是否收费
class _AcceptedOrder {
  const _AcceptedOrder({required this.order, required this.acceptedAt});

  final _FarmOrder order;
  final DateTime acceptedAt;
}

/// 接单确认弹窗：展示订单与取消规则，确认按钮 5 秒倒计时后才可点击
class _AcceptOrderDialog extends StatefulWidget {
  const _AcceptOrderDialog({required this.order});

  final _FarmOrder order;

  @override
  State<_AcceptOrderDialog> createState() => _AcceptOrderDialogState();
}

class _AcceptOrderDialogState extends State<_AcceptOrderDialog> {
  static const int _countdownSeconds = 5;

  int _remaining = _countdownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final fee = order.price * 0.02;
    return AlertDialog(
      title: const Text('确认接单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${order.crop} · ${order.area.toStringAsFixed(0)} 亩',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${order.village} · ${order.time}',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
          const SizedBox(height: 6),
          Text(
            '预估费用 ￥${order.price.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '接单满 12 小时后如需取消订单，需向农户支付订单金额 2% 的接单费用（约 ￥${fee.toStringAsFixed(0)}）。',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_remaining > 0)
            Text(
              '请先确认订单信息，$_remaining 秒后可点击「确定接单」',
              style: const TextStyle(fontSize: 12, color: AppColors.accent),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _remaining > 0 ? null : () => Navigator.of(context).pop(true),
          child: Text(_remaining > 0 ? '确定接单（$_remaining）' : '确定接单'),
        ),
      ],
    );
  }
}

/// 农户发布的作业订单
class _FarmOrder {
  const _FarmOrder({
    required this.crop,
    required this.area,
    required this.village,
    required this.time,
    required this.price,
  });

  final String crop;
  final double area;
  final String village;
  final String time;
  final double price;
}
