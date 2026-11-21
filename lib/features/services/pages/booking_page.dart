import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/accessibility/elder_care_reader.dart';
import '../../../core/theme/app_theme.dart';

/// 飞防预约：使用者填写作业信息，预约飞手上门喷洒农药
class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  static const List<String> _crops = ['油菜', '水稻', '小麦', '玉米', '果树', '其他'];
  static const List<String> _periods = ['上午', '下午'];

  static const List<_Pilot> _pilots = [
    _Pilot(name: '李师傅', rating: 4.9, orders: 326, distanceKm: 3.2, price: 8),
    _Pilot(name: '王师傅', rating: 4.8, orders: 208, distanceKm: 5.6, price: 7),
    _Pilot(name: '赵师傅', rating: 4.7, orders: 154, distanceKm: 8.1, price: 6),
  ];

  final _formKey = GlobalKey<FormState>();
  final _areaCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '8');
  final _addressCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _crop = _crops.first;
  String _period = _periods.first;
  _Pilot? _pilot = _pilots.first;
  String _sortField = '距离';
  bool _distanceAscending = true;
  bool _ratingAscending = false;
  DateTime _date = DateTime.now().add(const Duration(days: 1));

  /// 按当前排序字段与方向排列的飞手列表
  List<_Pilot> get _sortedPilots {
    final pilots = [..._pilots];
    if (_sortField == '评分') {
      pilots.sort((a, b) => _ratingAscending
          ? a.rating.compareTo(b.rating)
          : b.rating.compareTo(a.rating));
    } else {
      pilots.sort((a, b) => _distanceAscending
          ? a.distanceKm.compareTo(b.distanceKm)
          : b.distanceKm.compareTo(a.distanceKm));
    }
    return pilots;
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _priceCtrl.dispose();
    _addressCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 预估费用 = 作业面积 × 按亩单价，任一为空或非法时不显示
  double? get _estimatedCost {
    final area = double.tryParse(_areaCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (area == null || price == null || area <= 0 || price <= 0) {
      return null;
    }
    return area * price;
  }

  String get _estimatedText {
    final cost = _estimatedCost;
    if (cost == null) return '--';
    final text = cost == cost.roundToDouble()
        ? cost.toStringAsFixed(0)
        : cost.toStringAsFixed(2);
    return '￥$text';
  }

  String get _dateText =>
      '${_date.year}年${_date.month}月${_date.day}日 $_period';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      helpText: '选择作业日期',
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _submit() {
    final pilot = _pilot;
    if (pilot == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先选择飞手')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('预约已提交'),
        content: Text(
          '飞手：${pilot.name}\n作业时间：$_dateText\n作业地点：${_addressCtrl.text.trim()}\n作业面积：${_areaCtrl.text.trim()} 亩\n按亩单价：${_priceCtrl.text.trim()} 元/亩\n预估费用：$_estimatedText\n\n飞手确认后会电话联系你，请保持手机畅通。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预约飞防')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _banner(),
            const SizedBox(height: 20),
            _sectionTitle('选择飞手'),
            const SizedBox(height: 10),
            _pilotList(),
            const SizedBox(height: 20),
            _sectionTitle('作业信息'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '作物类型',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _crops.map(_cropChip).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _areaCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: '作业面积（亩）',
                            hintText: '例如 50',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请填写作业面积';
                            }
                            final area = double.tryParse(value.trim());
                            if (area == null || area <= 0) {
                              return '请填写正确的面积';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _priceCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: '按亩单价（元/亩）',
                            hintText: '例如 8',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请填写单价';
                            }
                            final price = double.tryParse(value.trim());
                            if (price == null || price <= 0) {
                              return '请填写正确的单价';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          size: 20,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '预估费用',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _estimatedText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: '作业地点',
                      hintText: '例如 湖北省荆州市监利市新沟镇 XX 村',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请填写作业地点';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('预约时间'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_date.year}年${_date.month}月${_date.day}日',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Text(
                            '修改日期',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Text(
                        '作业时段',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          children: _periods.map(_periodChip).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('联系方式'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '联系人',
                      hintText: '请填写称呼',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请填写联系人';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '用于飞手联系你',
                      counterText: '',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (!RegExp(r'^1\d{10}$').hasMatch(text)) {
                        return '请填写正确的 11 位手机号';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('备注（选填）'),
            const SizedBox(height: 10),
            _card(
              child: TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                maxLength: 100,
                decoration: const InputDecoration(
                  hintText: '例如：地块在村东头，有电线杆，请注意飞行安全',
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text(
                  '提交预约',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '提交后飞手会电话与你确认作业时间与价格，请勿重复预约。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner() {
    return ElderCareBlock(
      readText: '无人机植保预约。专业飞手、上门作业、按亩计价。',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.flight_takeoff,
                size: 26,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '无人机植保预约',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '专业飞手 · 上门作业 · 按亩计价',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _pilotList() {
    final pilots = _sortedPilots;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              children: [
                Text(
                  '共 ${pilots.length} 位飞手',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
                const Spacer(),
                _sortGroup(label: '距离', ascending: _distanceAscending),
                const SizedBox(width: 8),
                _sortGroup(label: '评分', ascending: _ratingAscending),
              ],
            ),
          ),
          for (var i = 0; i < pilots.length; i++) ...[
            const Divider(height: 1, indent: 58, endIndent: 14),
            _pilotRow(pilots[i]),
          ],
        ],
      ),
    );
  }

  /// 切换排序：按指定字段的升序 / 降序排列
  void _applySort(String label, bool ascending) {
    setState(() {
      _sortField = label;
      if (label == '距离') {
        _distanceAscending = ascending;
      } else {
        _ratingAscending = ascending;
      }
    });
  }

  /// 排序组：字段名 + 升序、降序两个图标
  Widget _sortGroup({required String label, required bool ascending}) {
    final active = _sortField == label;
    final color = active ? AppColors.primary : AppColors.textHint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
        const SizedBox(width: 2),
        _sortArrow(
          key: ValueKey('sort-$label-asc'),
          up: true,
          selected: active && ascending,
          onTap: () => _applySort(label, true),
        ),
        _sortArrow(
          key: ValueKey('sort-$label-desc'),
          up: false,
          selected: active && !ascending,
          onTap: () => _applySort(label, false),
        ),
      ],
    );
  }

  Widget _sortArrow({
    required Key key,
    required bool up,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: up ? '升序' : '降序',
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: selected ? AppColors.primary : AppColors.textHint,
          ),
        ),
      ),
    );
  }

  Widget _pilotRow(_Pilot pilot) {
    final selected = pilot.name == _pilot?.name;
    return ElderCareBlock(
      readText:
          '飞手${pilot.name}，评分${pilot.rating.toStringAsFixed(1)}，已接${pilot.orders}单，距你${pilot.distanceKm}公里，单价${pilot.price.toStringAsFixed(0)}元每亩',
      child: Material(
        color: selected
            ? AppColors.primaryLight.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _pilot = pilot),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    pilot.name.substring(0, 1),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            pilot.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            pilot.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '已接 ${pilot.orders} 单 · 距你 ${pilot.distanceKm} km · ${pilot.price.toStringAsFixed(0)} 元/亩',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cropChip(String crop) {
    final selected = crop == _crop;
    return ChoiceChip(
      label: Text(crop),
      selected: selected,
      onSelected: (_) => setState(() => _crop = crop),
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? AppColors.textOnPrimary : AppColors.textSecondary,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceVariant,
      side: BorderSide.none,
      showCheckmark: false,
    );
  }

  Widget _periodChip(String period) {
    final selected = period == _period;
    return ChoiceChip(
      label: Text(period),
      selected: selected,
      onSelected: (_) => setState(() => _period = period),
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? AppColors.textOnPrimary : AppColors.textSecondary,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceVariant,
      side: BorderSide.none,
      showCheckmark: false,
    );
  }
}

/// 可预约的飞手信息
class _Pilot {
  const _Pilot({
    required this.name,
    required this.rating,
    required this.orders,
    required this.distanceKm,
    required this.price,
  });

  final String name;
  final double rating;
  final int orders;
  final double distanceKm;

  /// 按亩单价（元/亩）
  final double price;
}
