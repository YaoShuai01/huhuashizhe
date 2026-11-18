import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coord_transform.dart';
import '../../../services/gps_location_service.dart';
import '../../../services/satellite_service.dart';
import '../widgets/speedometer_painters.dart';

/// 北斗/GPS 搜星界面（横屏）
///
/// - 默认展示卫星罗盘，可切换到卫星地图
/// - 罗盘跟随手机朝向旋转，始终指北
/// - 卫星数量、方位、仰角、信噪比来自手机 GNSS 实时数据
/// - 机载北斗模块接入前，先使用手机 GNSS 搜星
class GpsSpeedometerPage extends StatefulWidget {
  const GpsSpeedometerPage({super.key});

  @override
  State<GpsSpeedometerPage> createState() => _GpsSpeedometerPageState();
}

class _GpsSpeedometerPageState extends State<GpsSpeedometerPage>
    with TickerProviderStateMixin {
  static const LatLng _fallbackCenter = LatLng(31.2304, 121.4737);
  static const double _zoom = 16;

  late final AnimationController _pulseCtrl;
  late final AnimationController _sweepCtrl;
  final MapController _mapController = MapController();

  /// 默认展示卫星罗盘（搜星）
  bool _mapMode = false;
  bool _beidou = true;
  bool _mapReady = false;
  bool _locating = false;
  bool _permissionDenied = false;
  String? _gnssError;

  GnssSnapshot? _gnss;
  double _heading = 0;
  GpsLocation? _location;

  StreamSubscription<GnssSnapshot>? _gnssSub;
  StreamSubscription<double>? _headingSub;

  /// 高德卫星瓦片使用 GCJ-02 坐标
  LatLng _center = _initialCenter();

  // 跟随 App 深浅色主题的页面色板
  bool _dark = true;
  Color _bgTop = const Color(0xFF0E1812);
  Color _bgMid = const Color(0xFF15231A);
  Color _bgBottom = const Color(0xFF0A100C);
  Color _cardColor = const Color(0xFF1E2A22);
  Color _cardBorder = Colors.white12;
  Color _textPrimary = const Color(0xFFE8F0E9);
  Color _textSecondary = Colors.white70;
  Color _textMuted = Colors.white38;
  Color _green = AppColors.primaryLight;
  Color _amber = AppColors.accent;

  static LatLng _initialCenter() {
    final cached = GpsLocationService.cachedLocation;
    if (cached == null) return _fallbackCenter;
    return CoordTransform.wgs84ToGcj02(cached.lat, cached.lng);
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initSensors();
    });
  }

  @override
  void dispose() {
    _gnssSub?.cancel();
    _headingSub?.cancel();
    _pulseCtrl.dispose();
    _sweepCtrl.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _initSensors() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
    } catch (_) {
      // 测试环境或精简系统没有权限插件时，继续尝试订阅原生事件
    }

    _gnssSub ??= SatelliteService.gnssStream.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _gnss = snapshot;
          _gnssError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _gnssError = error.toString());
      },
    );

    _headingSub ??= SatelliteService.headingStream.listen(
      (heading) {
        if (!mounted) return;
        setState(() => _heading = heading);
      },
      onError: (Object error) {
        // 没有方向传感器时保持上一次朝向，不打断搜星
      },
    );

    await _locate();
  }

  Future<void> _retryPermission() async {
    setState(() {
      _permissionDenied = false;
      _gnssError = null;
    });
    await _initSensors();
  }

  /// 卫星定位：GPS 返回 WGS-84，转换为 GCJ-02 后再上图
  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final loc = await GpsLocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _locating = false);
      return;
    }
    final gcj = CoordTransform.wgs84ToGcj02(loc.lat, loc.lng);
    setState(() {
      _location = loc;
      _center = gcj;
      _locating = false;
    });
    if (_mapReady) {
      _mapController.move(gcj, _zoom);
    }
  }

  List<GnssSatellite> get _selectedSats {
    final snapshot = _gnss;
    if (snapshot == null) return const [];
    final list = snapshot.satellitesOf(_beidou ? 'beidou' : 'gps');
    // 过滤掉尚未收到信号的空卫星，避免“搜到”数量虚高
    return list
        .where((sat) => sat.snr > 0 || sat.usedInFix)
        .toList(growable: false);
  }

  int get _foundCount => _selectedSats.length;

  int get _usedCount => _selectedSats.where((s) => s.usedInFix).length;

  String get _systemName => _beidou ? '北斗' : 'GPS';

  GnssSatellite? get _strongestSat {
    GnssSatellite? strongest;
    for (final sat in _selectedSats) {
      if (strongest == null || sat.snr > strongest.snr) strongest = sat;
    }
    return strongest;
  }

  void _applyTheme(BuildContext context) {
    _dark = Theme.of(context).brightness == Brightness.dark;
    if (_dark) {
      _bgTop = const Color(0xFF0E1812);
      _bgMid = const Color(0xFF15231A);
      _bgBottom = const Color(0xFF0A100C);
      _cardColor = const Color(0xFF1E2A22);
      _cardBorder = Colors.white.withValues(alpha: 0.08);
      _textPrimary = const Color(0xFFE8F0E9);
      _textSecondary = Colors.white.withValues(alpha: 0.70);
      _textMuted = Colors.white.withValues(alpha: 0.42);
      _green = AppColors.primaryLight;
      _amber = AppColors.accent;
    } else {
      _bgTop = AppColors.background;
      _bgMid = const Color(0xFFEAF3EC);
      _bgBottom = AppColors.background;
      _cardColor = AppColors.surface;
      _cardBorder = AppColors.primary.withValues(alpha: 0.14);
      _textPrimary = AppColors.textPrimary;
      _textSecondary = AppColors.textSecondary;
      _textMuted = AppColors.textHint;
      _green = AppColors.primary;
      _amber = AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    _applyTheme(context);
    return Scaffold(
      backgroundColor: _bgMid,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgMid, _bgBottom],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildAmbientGlow(),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final panelWidth =
                            math.min(280.0, constraints.maxWidth * 0.30);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _mapMode
                                    ? _buildMapCard()
                                    : _buildCompassCard(),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: panelWidth,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildViewSwitch(),
                                    const Spacer(),
                                    _buildLocateButton(),
                                    const SizedBox(height: 10),
                                    _sourceButton(
                                      label: '北斗卫星',
                                      icon: Icons.satellite_alt,
                                      color: _green,
                                      active: _beidou,
                                      onTap: () =>
                                          setState(() => _beidou = true),
                                    ),
                                    const SizedBox(height: 10),
                                    _sourceButton(
                                      label: 'GPS',
                                      icon: Icons.gps_fixed,
                                      color: _amber,
                                      active: !_beidou,
                                      onTap: () =>
                                          setState(() => _beidou = false),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '当前使用手机 GNSS\n机载北斗模块未接入',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _textMuted,
                                        fontSize: 11,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          Material(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back, color: _textPrimary, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '北斗 / GPS 搜星',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$_systemName · ${_permissionDenied ? '等待定位权限' : (_foundCount == 0 ? '正在搜索卫星' : '已搜到 $_foundCount 颗，使用 $_usedCount 颗')}',
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          _liveChip(),
        ],
      ),
    );
  }

  Widget _buildAmbientGlow() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -140,
            top: -80,
            child: _glowOrb(380, _green, _dark ? 0.18 : 0.10),
          ),
          Positioned(
            right: -160,
            bottom: -120,
            child: _glowOrb(420, _amber, _dark ? 0.08 : 0.05),
          ),
        ],
      ),
    );
  }

  Widget _glowOrb(double size, Color color, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), Colors.transparent],
        ),
      ),
    );
  }

  Widget _glass({required Widget child, double radius = 16}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _cardColor.withValues(alpha: _dark ? 0.88 : 0.94),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _cardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _dark ? 0.35 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// 地图 / 罗盘 视图切换（罗盘在前，便于搜星时快速切换）
  Widget _buildViewSwitch() {
    Widget segment(String label, bool mapMode) {
      final active = _mapMode == mapMode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _mapMode = mapMode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active
                  ? _green.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? _green.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? _green : _textMuted,
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      );
    }

    return _glass(
      radius: 14,
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              segment('卫星罗盘', false),
              segment('卫星地图', true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompassCard() {
    final sats = _selectedSats
        .map((sat) => SatelliteInfo(
              azimuth: sat.azimuth,
              // 仰角 90°（天顶）在圆心，0°（地平线）在边缘
              elevation: (1 - sat.elevation.clamp(0.0, 90.0) / 90.0)
                  .clamp(0.0, 1.0),
              prn: sat.svid,
              locked: sat.usedInFix,
              strong: sat.snr >= 30,
            ))
        .toList(growable: false);
    final strongest = _strongestSat;

    return _glass(
      radius: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              left: -40,
              top: -40,
              child: _glowOrb(260, _green, _dark ? 0.10 : 0.06),
            ),
            Positioned(
              right: -60,
              bottom: -60,
              child: _glowOrb(280, _amber, _dark ? 0.07 : 0.04),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                  child: Row(
                    children: [
                      _statLabel('搜到 $_foundCount', _textSecondary),
                      Expanded(child: Center(child: _liveChip())),
                      _statLabel('使用 $_usedCount', _green, glow: true),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = math.min(
                          constraints.maxWidth, constraints.maxHeight);
                      final radius = side / 2 - side * 0.095;
                      return Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Transform.rotate(
                                  angle: -_heading * math.pi / 180,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: AnimatedBuilder(
                                          animation: _sweepCtrl,
                                          builder: (context, _) => CustomPaint(
                                            painter: SkyPlotPainter(
                                              satellites: sats,
                                              sweep:
                                                  _sweepCtrl.value * 2 * math.pi,
                                              green: _green,
                                              amber: _amber,
                                              muted: _textMuted,
                                              tickColor: _textSecondary,
                                              dark: _dark,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _compassLabel('北', 0, side, radius,
                                          north: true),
                                      _compassLabel('东', 90, side, radius),
                                      _compassLabel('南', 180, side, radius),
                                      _compassLabel('西', 270, side, radius),
                                    ],
                                  ),
                                ),
                              ),
                              if (_permissionDenied)
                                Positioned.fill(child: _buildPermissionOverlay())
                              else if (sats.isEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Center(
                                      child: _buildSearchingOverlay(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
                  child: Row(
                    children: [
                      _telemetry(
                        'PRN',
                        strongest == null
                            ? '--'
                            : strongest.svid.toString().padLeft(2, '0'),
                      ),
                      const SizedBox(width: 18),
                      _telemetry(
                        'SNR',
                        strongest == null
                            ? '--'
                            : '${strongest.snr.toStringAsFixed(0)} dB',
                      ),
                      const Spacer(),
                      _telemetry(
                        'FIX',
                        _usedCount >= 4
                            ? '3D'
                            : (_usedCount > 0 ? '2D' : '--'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ..._hudCorners(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingOverlay() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _sweepCtrl,
          builder: (context, _) => Transform.rotate(
            angle: _sweepCtrl.value * 2 * math.pi,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _green.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.16),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Icon(Icons.satellite_alt, color: _green, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '正在搜星…',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '请到空旷处等待 $_systemName 卫星锁定',
          style: TextStyle(color: _textSecondary, fontSize: 12),
        ),
        if (_gnssError != null) ...[
          const SizedBox(height: 4),
          Text(
            _gnssError!,
            style: TextStyle(color: _amber, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildPermissionOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, color: _amber, size: 30),
            const SizedBox(height: 10),
            Text(
              '需要定位权限才能搜星',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请在系统设置中允许“护花使者”使用位置信息',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _retryPermission,
              child: Text('授权定位', style: TextStyle(color: _green)),
            ),
          ],
        ),
      ),
    );
  }

  /// 罗盘方位字（用 Text 绘制，确保中文字体正常）
  Widget _compassLabel(
    String text,
    int deg,
    double side,
    double radius, {
    bool north = false,
  }) {
    final rad = deg * math.pi / 180;
    final labelR = radius + side * 0.048;
    const box = 32.0;
    final center = side / 2;
    final color = north ? _amber : _green;
    return Positioned(
      left: center + math.sin(rad) * labelR - box / 2,
      top: center - math.cos(rad) * labelR - box / 2,
      width: box,
      height: box,
      child: IgnorePointer(
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: side * 0.042,
              fontWeight: FontWeight.w600,
              height: 1,
              shadows: _dark
                  ? [Shadow(color: color.withValues(alpha: 0.75), blurRadius: 10)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapCard() {
    return _glass(
      radius: 18,
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                minZoom: 3,
                maxZoom: 18,
                backgroundColor: const Color(0xFF101713),
                onMapReady: () => _mapReady = true,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
                  subdomains: const ['1', '2', '3', '4'],
                  userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
                  maxZoom: 18,
                ),
                if (_location != null) ...[
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _center,
                        radius: math.max(
                          _location!.accuracy > 0 &&
                                  _location!.accuracy.isFinite
                              ? _location!.accuracy
                              : 5,
                          5,
                        ),
                        useRadiusInMeter: true,
                        color: _green.withValues(alpha: 0.10),
                        borderColor: _green.withValues(alpha: 0.35),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _center,
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        child: Center(child: _positionMarker()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // 上下渐变压暗，保证浮层文字可读
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 68,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 64,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 28,
            right: 28,
            child: Row(
              children: [
                _statusIndicator(onMap: true),
                const Spacer(),
                _liveChip(color: Colors.white70),
                const Spacer(),
                _statLabel(
                  _location == null
                      ? '精度 --'
                      : '精度 ±${_location!.accuracy.toStringAsFixed(1)} m',
                  Colors.white.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 14,
            child: Row(
              children: [
                _telemetry(
                  '纬度',
                  _location == null
                      ? '--'
                      : _center.latitude.toStringAsFixed(6),
                  labelColor: Colors.white70,
                  valueColor: Colors.white,
                ),
                const SizedBox(width: 18),
                _telemetry(
                  '经度',
                  _location == null
                      ? '--'
                      : _center.longitude.toStringAsFixed(6),
                  labelColor: Colors.white70,
                  valueColor: Colors.white,
                ),
                const Spacer(),
                _telemetry(
                  '卫星',
                  _gnss == null ? '--' : '${_gnss!.total}',
                  labelColor: Colors.white70,
                  valueColor: Colors.white,
                ),
              ],
            ),
          ),
          ..._hudCorners(),
        ],
      ),
    );
  }

  /// 当前位置标记（呼吸光圈 + 实心点）
  Widget _positionMarker() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final t = _pulseCtrl.value;
        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 20 + 28 * t,
                height: 20 + 28 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _green.withValues(alpha: 0.55 * (1 - t)),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.7),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 定位状态指示
  Widget _statusIndicator({bool onMap = false}) {
    final String text;
    final Color color;
    if (_permissionDenied) {
      text = '未授权';
      color = onMap ? AppColors.accent : _amber;
    } else if (_locating) {
      text = '定位中';
      color = onMap ? AppColors.accent : _amber;
    } else if (_location != null) {
      text = '已定位';
      color = onMap ? AppColors.primaryLight : _green;
    } else {
      text = '未定位';
      color = Colors.white.withValues(alpha: 0.65);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _liveChip({Color? color}) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulse =
            0.45 + 0.55 * (0.5 + 0.5 * math.sin(_pulseCtrl.value * 2 * math.pi));
        return Text(
          'LIVE',
          style: TextStyle(
            color: (color ?? _textSecondary).withValues(alpha: pulse),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            letterSpacing: 2,
          ),
        );
      },
    );
  }

  Widget _buildLocateButton() {
    final foreground = _dark ? const Color(0xFF12200F) : Colors.white;
    return GestureDetector(
      key: const Key('locate_button'),
      behavior: HitTestBehavior.opaque,
      onTap: _locating ? null : _locate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        decoration: BoxDecoration(
          color: _green.withValues(alpha: _locating ? 0.14 : 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _green.withValues(alpha: 0.85)),
          boxShadow: _locating
              ? null
              : [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_locating)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_green),
                ),
              )
            else
              Icon(Icons.my_location, size: 20, color: foreground),
            const SizedBox(width: 8),
            Text(
              _locating ? '定位中…' : '定位',
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.16)
              : _cardColor.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.55) : _cardBorder,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? color : _textMuted,
              shadows: active && _dark
                  ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)]
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? color : _textMuted,
                fontSize: 16,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 1.2,
                shadows: active && _dark
                    ? [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hudCorners() {
    Widget corner({required bool top, required bool left}) {
      final side = BorderSide(color: _green.withValues(alpha: 0.45), width: 1.2);
      return Positioned(
        top: top ? 9 : null,
        bottom: top ? null : 9,
        left: left ? 9 : null,
        right: left ? null : 9,
        child: IgnorePointer(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              border: Border(
                top: top ? side : BorderSide.none,
                bottom: top ? BorderSide.none : side,
                left: left ? side : BorderSide.none,
                right: left ? BorderSide.none : side,
              ),
            ),
          ),
        ),
      );
    }

    return [
      corner(top: true, left: true),
      corner(top: true, left: false),
      corner(top: false, left: true),
      corner(top: false, left: false),
    ];
  }

  Widget _telemetry(
    String label,
    String value, {
    Color? labelColor,
    Color? valueColor,
  }) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: labelColor ?? _textSecondary,
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 0.8,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? _textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statLabel(String text, Color color, {bool glow = false}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        shadows: glow && _dark
            ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)]
            : null,
      ),
    );
  }
}
