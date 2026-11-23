import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_api.dart';
import '../data/auth_session.dart';

/// 登录 / 设置密码（注册后系统自动生成登录号）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.api, this.session});

  /// 外部注入接口，为空时使用默认后端
  final AuthApi? api;

  /// 外部注入登录状态，为空时使用全局实例
  final AuthSession? session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginIdController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  late final AuthApi _api = widget.api ?? DioAuthApi();
  late final AuthSession _session = widget.session ?? AuthSession.instance;

  /// true 表示「设置密码」页（默认先展示未注册用户），false 表示「登录」
  bool _registerMode = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _loginIdController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final password = _passwordController.text;

    setState(() => _submitting = true);
    try {
      final user =
          _registerMode
              ? await _api.register(
                nickname: _nicknameController.text.trim(),
                password: password,
              )
              : await _api.login(
                loginId: _loginIdController.text.trim(),
                password: password,
              );
      _session.signIn(user);
      if (!mounted) return;
      Navigator.of(context).pop(user);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _switchMode() {
    setState(() {
      _registerMode = !_registerMode;
      _error = null;
      _confirmController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_registerMode ? '设置密码' : '登录')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              if (_registerMode) ...[
                TextFormField(
                  controller: _nicknameController,
                  textInputAction: TextInputAction.next,
                  maxLength: 6,
                  decoration: _decoration(
                    label: '昵称',
                    hint: '5-6 个字',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return '请输入昵称';
                    if (text.runes.length < 5) return '昵称需为 5-6 个字';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ] else ...[
                TextFormField(
                  controller: _loginIdController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: '登录号',
                    hint: '8 位数字登录号',
                    icon: Icons.badge_outlined,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return '请输入登录号';
                    if (!RegExp(r'^\d{8}$').hasMatch(text)) {
                      return '登录号是 8 位数字';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                textInputAction:
                    _registerMode ? TextInputAction.next : TextInputAction.done,
                maxLength: 32,
                onFieldSubmitted: _registerMode ? null : (_) => _submit(),
                decoration: _decoration(
                  label: '密码',
                  hint: '6-32 位密码',
                  icon: Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: _obscure ? '显示密码' : '隐藏密码',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) return '请输入密码';
                  if (text.length < 6) return '密码至少 6 位';
                  return null;
                },
              ),
              if (_registerMode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  maxLength: 32,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration(
                    label: '确认密码',
                    hint: '再次输入密码',
                    icon: Icons.lock_outline,
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) return '请再次输入密码';
                    if (value != _passwordController.text) {
                      return '两次输入的密码不一致';
                    }
                    return null;
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _submitting
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textOnPrimary,
                            ),
                          )
                          : Text(
                            _registerMode ? '设置密码并生成登录号' : '登录',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _submitting ? null : _switchMode,
                child: Text(
                  _registerMode ? '已有登录号？去登录' : '首次使用？设置密码',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.eco, size: 38, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          _registerMode ? '设置密码，自动生成登录号' : '欢迎回来',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _registerMode ? '昵称用于展示，登录号由系统分配' : '使用登录号和密码登录',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textHint),
        ),
      ],
    );
  }

  InputDecoration _decoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
      prefixIcon: Icon(icon, size: 20, color: AppColors.textHint),
      filled: true,
      fillColor: AppColors.surface,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
