import 'package:flutter/material.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';

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
  List<_FarmOrder> _pending = List.of(_seedOrders);
  final List<_FarmOrder> _accepted = [];

  void _accept(_FarmOrder order) {
    setState(() {
      _pending = _pending.where((item) => item != order).toList();
      _accepted.insert(0, order);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已接单，请尽快联系农户确认作业时间')),
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
              title: Text(
                '接受新订单',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
              subtitle: Text(
                '关闭后不再展示新的农户订单',
                style: TextStyle(fontSize: 12, color: context.palette.textHint),
              ),
            ),
          ),
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
          Text(
            '附近订单',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_pending.isEmpty)
            _emptyCard('暂无待接订单，稍后再来看看')
          else
            for (final order in _pending) _orderCard(order),
          const SizedBox(height: 20),
          Text(
            '我的接单',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_accepted.isEmpty)
            _emptyCard('还没有接单，接单后会展示在这里')
          else
            for (final order in _accepted) _acceptedCard(order),
        ],
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
              style: TextStyle(
                fontSize: 12,
                color: context.palette.textHint,
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
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.palette.textPrimary,
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

  Widget _acceptedCard(_FarmOrder order) {
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.village} · ${order.time}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: context.palette.textHint),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          ),
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
