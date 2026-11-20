import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/wifi_service.dart';

/// 设备连接页：扫描周边 WiFi，引导连接无人机热点
///
/// Android 10+ 禁止应用直接连接指定 WiFi，因此点击网络后跳系统 WiFi 面板，
/// 返回 APP 时自动检测是否已连上 HuHuaShiZhe-Drone。
class WifiScanPage extends StatefulWidget {
  const WifiScanPage({super.key});

  @override
  State<WifiScanPage> createState() => _WifiScanPageState();
}

class _WifiScanPageState extends State<WifiScanPage> with WidgetsBindingObserver {
  final WifiService _wifiService = WifiService();
  bool _isScanning = false;
  bool _wifiEnabled = true;
  String _errorMessage = '';
  WifiStatus _status = const WifiStatus();
  final List<WifiNetwork> _networks = [];
  StreamSubscription<WifiNetwork>? _networkSub;
  StreamSubscription<void>? _scanCompleteSub;
  StreamSubscription<WifiStatus>? _statusSub;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wifiService.init();
    _networkSub = _wifiService.networkStream.listen(_onNetworkFound);
    _scanCompleteSub = _wifiService.scanCompleteStream.listen((_) {
      if (mounted) setState(() => _isScanning = false);
    });
    _statusSub = _wifiService.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _initPage();
  }

  Future<void> _initPage() async {
    final enabled = await _wifiService.isWifiEnabled();
    if (!mounted) return;
    setState(() => _wifiEnabled = enabled);
    if (enabled) {
      await _startScan();
    } else {
      _showError('WiFi 未开启，请先在系统设置中打开 WiFi');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统 WiFi 面板返回后重新检测连接并刷新列表
    if (state == AppLifecycleState.resumed) {
      _refreshConnection();
    }
  }

  Future<void> _refreshConnection() async {
    final enabled = await _wifiService.isWifiEnabled();
    await _wifiService.refreshStatus();
    if (!mounted) return;
    setState(() => _wifiEnabled = enabled);
    if (enabled) await _startScan();
  }

  void _onNetworkFound(WifiNetwork network) {
    if (!mounted) return;
    setState(() {
      final index = _networks.indexWhere((n) => n.bssid == network.bssid);
      if (index >= 0) {
        _networks[index] = network;
      } else {
        _networks.add(network);
      }
      // 无人机热点置顶，其余按信号强度排序
      _networks.sort((a, b) {
        if (a.isDrone != b.isDrone) return a.isDrone ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
    });
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _errorMessage = '');
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _networks.clear();
      _errorMessage = '';
    });

    try {
      final success = await _wifiService.startScan();
      if (!success && mounted) {
        setState(() => _isScanning = false);
        _showError('扫描启动失败，请检查 WiFi 与定位权限');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      switch (e.code) {
        case 'WIFI_DISABLED':
 setState(() => _wifiEnabled = false);
          _showError('WiFi 未开启，请先打开 WiFi');
          break;
        case 'NO_PERMISSION':
 _showError('缺少 WiFi 扫描权限，请在系统设置中授权');
          break;
        default:
 _showError('扫描失败: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError('扫描失败: $e');
      }
    }
  }

  Future<void> _onConnectTap(WifiNetwork network) async {
    if (network.isCurrent) {
      await _wifiService.refreshStatus();
      if (mounted) _showConnectedHint();
      return;
    }
    await _wifiService.openWifiSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(network.isDrone
            ? '请在系统面板中选择 ${network.ssid} 完成连接，返回后自动刷新'
            : '请在系统面板中选择 ${network.ssid} 完成连接'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showConnectedHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已连接无人机热点，可返回首页开始作业'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel();
    _scanCompleteSub?.cancel();
    _statusSub?.cancel();
    _errorTimer?.cancel();
    _wifiService.stopScan();
    _wifiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备连接'),
        actions: [
          IconButton(
            onPressed: _isScanning ? null : _refreshConnection,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新连接状态',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConnectionCard(),
          Container(
            padding: const EdgeInsets.all(16),
            color: context.palette.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isScanning ? '正在扫描周边 WiFi...' : '${_networks.length} 个网络已发现',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: Icon(_isScanning ? Icons.hourglass_empty : Icons.wifi_find),
                  label: Text(_isScanning ? '扫描中...' : '扫描 WiFi'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          if (!_wifiEnabled) _buildWarningBanner(),
          if (_errorMessage.isNotEmpty) _buildErrorBanner(),
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(
            child: _networks.isEmpty && !_isScanning
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _networks.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) => _buildNetworkCard(_networks[index]),
                  ),
          ),
          _buildBottomHint(),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    final connected = _status.isConnected;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (connected ? AppColors.primary : AppColors.warning).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (connected ? AppColors.primary : AppColors.warning).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? AppColors.primary : AppColors.warning,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? '已连接：${_status.displayName}' : '未连接无人机热点',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: connected ? AppColors.primary : AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  connected
                      ? '信号 ${_status.signalDisplay} · 可返回首页开始作业'
                      : '请连接 ${WifiService.droneSsid}（默认密码见机身标签）',
                  style:  TextStyle(fontSize: 12, color: context.palette.textSecondary),
                ),
              ],
            ),
          ),
          if (connected)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'WiFi 未开启，请在系统设置中打开 WiFi 后重试',
              style: TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage, style: const TextStyle(fontSize: 13, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 64, color: context.palette.textDisabled.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
           Text('未发现 WiFi 网络', style: TextStyle(fontSize: 16, color: context.palette.textHint)),
          const SizedBox(height: 8),
           Text(
            '请确认无人机已上电，并已开启手机定位服务\n（Android 扫描 WiFi 需要定位服务）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.palette.textDisabled),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _startScan,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(WifiNetwork network) {
    final isDrone = network.isDrone;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDrone
            ? BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isDrone ? AppColors.primary : AppColors.primaryLight).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _signalIcon(network.rssi),
            color: isDrone ? AppColors.primary : context.palette.textSecondary,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                network.ssid,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDrone) ...[
              const SizedBox(width: 6),
              _badge('无人机', AppColors.primary),
            ],
            if (network.isCurrent) ...[
              const SizedBox(width: 6),
              _badge('已连接', Colors.green),
            ],
          ],
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                '${network.securityDisplay} · 信号 ${network.signalDisplay}',
                style:  TextStyle(fontSize: 12, color: context.palette.textHint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: network.isCurrent ? null : () => _onConnectTap(network),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
          ),
          child: Text(network.isCurrent ? '已连接' : '连接', style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _buildBottomHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: context.palette.background,
      child:  Text(
        'Android 10 及以上系统不允许 APP 直接连接 WiFi：点击网络后请在系统面板中完成连接，返回本页会自动检测。',
        style: TextStyle(fontSize: 11, color: context.palette.textDisabled),
      ),
    );
  }

  IconData _signalIcon(int rssi) {
    if (rssi >= -55) return Icons.network_wifi;
    if (rssi >= -70) return Icons.network_wifi_3_bar;
    if (rssi >= -85) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }
}
