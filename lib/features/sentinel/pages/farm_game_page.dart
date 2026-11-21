import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// 田哨农场：内置的云种植农场游戏（WebView 加载本地资产）
///
/// 游戏为单文件 HTML（assets/sentinel_farm/index.html），
/// 与田哨预警联动：实地种植同步云田块、预警触发农场巡查处置。
class FarmGamePage extends StatefulWidget {
  const FarmGamePage({super.key});

  @override
  State<FarmGamePage> createState() => _FarmGamePageState();
}

class _FarmGamePageState extends State<FarmGamePage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadFlutterAsset('assets/sentinel_farm/index.html');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('田哨农场'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新载入',
            onPressed: () {
              setState(() => _loading = true);
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('农场加载中…', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
