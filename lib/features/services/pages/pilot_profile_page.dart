import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// 飞手资料
class PilotProfile {
  const PilotProfile({
    required this.name,
    required this.phone,
    required this.region,
    required this.droneModel,
    required this.pricePerMu,
    required this.years,
  });

  final String name;
  final String phone;
  final String region;
  final String droneModel;
  final double pricePerMu;
  final int years;
}

/// 飞手资料存储：退出页面后仍保留
class PilotProfileStore {
  static PilotProfile? current;
}

/// 飞手资料填写页
class PilotProfilePage extends StatefulWidget {
  const PilotProfilePage({super.key});

  @override
  State<PilotProfilePage> createState() => _PilotProfilePageState();
}

class _PilotProfilePageState extends State<PilotProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _region;
  late final TextEditingController _droneModel;
  late final TextEditingController _price;
  late final TextEditingController _years;

  @override
  void initState() {
    super.initState();
    final profile = PilotProfileStore.current;
    _name = TextEditingController(text: profile?.name ?? '');
    _phone = TextEditingController(text: profile?.phone ?? '');
    _region = TextEditingController(text: profile?.region ?? '');
    _droneModel = TextEditingController(text: profile?.droneModel ?? '');
    _price = TextEditingController(
      text: profile == null ? '' : profile.pricePerMu.toStringAsFixed(0),
    );
    _years = TextEditingController(
      text: profile == null ? '' : '${profile.years}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _region.dispose();
    _droneModel.dispose();
    _price.dispose();
    _years.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    PilotProfileStore.current = PilotProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      region: _region.text.trim(),
      droneModel: _droneModel.text.trim().isEmpty
          ? '未填写'
          : _droneModel.text.trim(),
      pricePerMu: double.parse(_price.text.trim()),
      years: int.parse(_years.text.trim()),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('飞手资料已保存')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('飞手资料')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              '完善资料后可被更多农户找到',
              style: TextStyle(fontSize: 13, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            _field(
              controller: _name,
              label: '姓名',
              hint: '请填写真实姓名',
              requiredMessage: '请填写姓名',
            ),
            const SizedBox(height: 14),
            _field(
              controller: _phone,
              label: '手机号',
              hint: '用于农户联系',
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '请填写手机号';
                if (text.length != 11) return '手机号应为 11 位';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _field(
              controller: _region,
              label: '服务区域',
              hint: '如：监利市新沟镇',
              requiredMessage: '请填写服务区域',
            ),
            const SizedBox(height: 14),
            _field(
              controller: _droneModel,
              label: '无人机机型（选填）',
              hint: '如：大疆 T50',
            ),
            const SizedBox(height: 14),
            _field(
              controller: _price,
              label: '每亩报价（元）',
              hint: '如：8',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '请填写每亩报价';
                final price = double.tryParse(text);
                if (price == null || price <= 0) return '请输入正确的报价';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _field(
              controller: _years,
              label: '从业年限',
              hint: '如：3',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '请填写从业年限';
                if (int.tryParse(text) == null) return '请输入数字';
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('保存资料'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? requiredMessage,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator ??
          (requiredMessage == null
              ? null
              : (value) =>
                  (value?.trim() ?? '').isEmpty ? requiredMessage : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
    );
  }
}
