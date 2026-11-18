import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/coord_transform.dart';
import '../../../services/gps_location_service.dart';
import '../widgets/speedometer_painters.dart';

/// 卫星地图 / 卫星罗盘界面（横屏 · 真实卫星瓦片 + GPS/北斗定位）
class GpsSpeedometerPage extends StatefulWidget {
  const GpsSpeedometerPage({super.key});

  @override
  State<GpsSpeedometerPage> createState() => _GpsSpeedometerPageState();
}

class _GpsSpeedometerPageState extends State<GpsSpeedometerPage>
    with TickerProviderStateMixin {
  static const Color _green = AppColors.primaryLight;
  static const Color _amber = AppColors.accent;
  static const Color _muted = Color(0xFF8A9690);

  static const LatLng _fallbackCenter = LatLng(31.2304, 121.4737);
  static const double _zoom = 16;

  late final AnimationController _pulseCtrl;
  late final AnimationController _sweepCtrl;
  final MapController _mapController = MapController();

  bool _mapMode = true;
  bool _beidou = true;
  bool _mapReady = false;
  bool _locating = false;
  GpsLocation? _location;

  static const List<SatelliteInfo> _satellites = [
    SatelliteInfo(azimuth: 336, elevation: 0.58, prn: 19),
    SatelliteInfo(azimuth: 316, elevation: 0.72, prn: 24, strong: true),
    SatelliteInfo(azimuth: 304, elevation: 0.50, prn: 14),
    SatelliteInfo(azimuth: 293, elevation: 0.78, prn: 20, strong: true),
    SatelliteInfo(azimuth: 263, elevation: 0.86, prn: 22, strong: true),
    SatelliteInfo(azimuth: 243, elevation: 0.67, prn: 5),
    SatelliteInfo(azimuth: 226, elevation: 0.86, prn: 25),
    SatelliteInfo(azimuth: 207, elevation: 0.74, prn: 9),
    SatelliteInfo(azimuth: 185, elevation: 0.56, prn: 21),
    SatelliteInfo(azimuth: 178, elevation: 0.78, prn: 26),
    SatelliteInfo(azimuth: 158, elevation: 0.86, prn: 3, strong: true),
    SatelliteInfo(azimuth: 137, elevation: 0.76, prn: 16),
    SatelliteInfo(azimuth: 118, elevation: 0.81, prn: 27),
    SatelliteInfo(azimuth: 105, elevation: 0.85, prn: 4),
    SatelliteInfo(azimuth: 90, elevation: 0.62, prn: 28),
    SatelliteInfo(azimuth: 77, elevation: 0.82, prn: 2),
    SatelliteInfo(azimuth: 61, elevation: 0.71, prn: 6),
    SatelliteInfo(azimuth: 58, elevation: 0.40, prn: 18),
    SatelliteInfo(azimuth: 50, elevation: 0.22, prn: 7),
    SatelliteInfo(azimuth: 28, elevation: 0.46, prn: 29),
    SatelliteInfo(azimuth: 19, elevation: 0.31, prn: 30),
    SatelliteInfo(azimuth: 0, elevation: 0.14, prn: 8),
    SatelliteInfo(azimuth: 320, elevation: 0.32, prn: 11),
    SatelliteInfo(azimuth: 280, elevation: 0.26, prn: 13),
    SatelliteInfo(azimuth: 240, elevation: 0.30, prn: 1),
    SatelliteInfo(azimuth: 200, elevation: 0.26, prn: 10),
    SatelliteInfo(azimuth: 160, elevation: 0.26, prn: 15),
    SatelliteInfo(azimuth: 94, elevation: 0.46, prn: 23),
  ];

  /// 高德卫星瓦片使用 GCJ-02 坐标
  LatLng _center = _initialCenter();

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
      if (mounted) _locate();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sweepCtrl.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B120F), Color(0xFF16201A), Color(0xFF090D0B)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildAmbientGlow(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final panelWidth =
                      math.min(300.0, constraints.maxWidth * 0.32);
                  return Padding(
                    padding: const EdgeInsets.all(14),
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                onTap: () => setState(() => _beidou = true),
                              ),
                              const SizedBox(height: 10),
                              _sourceButton(
                                label: 'GPS',
                                icon: Icons.gps_fixed,
                                color: _amber,
                                active: !_beidou,
                                onTap: () => setState(() => _beidou = false),
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
    );
  }

  Widget _buildAmbientGlow() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -140,
            top: -80,
            child: _glowOrb(380, AppColors.primary, 0.20),
          ),
          Positioned(
            right: -160,
            bottom: -120,
            child: _glowOrb(420, AppColors.accent, 0.08),
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

  Widget _glass({
    required Widget child,
    double radius = 16,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
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

  /// 地图 / 罗盘 视图切换
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
              color: active ? _green.withValues(alpha: 0.16) : Colors.transparent,
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
                color: active ? _green : Colors.white.withValues(alpha: 0.55),
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
              segment('卫星地图', true),
              segment('卫星罗盘', false),
            ],
          ),
        ),
      ),
    );
  }

  /// 卫星罗盘
  Widget _buildCompassCard() {
    return _glass(
      radius: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              left: -40,
              top: -40,
              child: _glowOrb(260, AppColors.primary, 0.10),
            ),
            Positioned(
              right: -60,
              bottom: -60,
              child: _glowOrb(280, AppColors.accent, 0.07),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
                  child: Row(
                    children: [
                      _statLabel('全部:28', Colors.white.withValues(alpha: 0.70)),
                      Expanded(child: Center(child: _liveChip())),
                      _statLabel('使用:0', _green, glow: true),
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
                                child: AnimatedBuilder(
                                  animation: _sweepCtrl,
                                  builder: (context, _) => CustomPaint(
                                    painter: SkyPlotPainter(
                                      satellites: _satellites,
                                      sweep: _sweepCtrl.value * 2 * math.pi,
                                    ),
                                  ),
                                ),
                              ),
                              _compassLabel('北', 0, side, radius, north: true),
                              _compassLabel('东', 90, side, radius),
                              _compassLabel('南', 180, side, radius),
                              _compassLabel('西', 270, side, radius),
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
                      _telemetry('PRN', '28'),
                      const SizedBox(width: 18),
                      _telemetry('SNR', '42 dB'),
                      const Spacer(),
                      _telemetry('FIX', '3D'),
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
              shadows: [
                Shadow(color: color.withValues(alpha: 0.75), blurRadius: 10),
              ],
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
                          _location!.accuracy > 0 && _location!.accuracy.isFinite
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
                _statusIndicator(),
                const Spacer(),
                _liveChip(),
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
                ),
                const SizedBox(width: 18),
                _telemetry(
                  '经度',
                  _location == null
                      ? '--'
                      : _center.longitude.toStringAsFixed(6),
                ),
                const Spacer(),
                _telemetry('卫星', _satelliteCount()),
              ],
            ),
          ),
          ..._hudCorners(),
        ],
      ),
    );
  }

  String _satelliteCount() {
    final sats = _location?.satellites;
    if (sats == null || sats.isEmpty) return '--';
    return sats.values.fold<int>(0, (a, b) => a + b).toString();
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
  Widget _statusIndicator() {
    final String text;
    final Color color;
    if (_locating) {
      text = '定位中';
      color = _amber;
    } else if (_location != null) {
      text = '已定位';
      color = _green;
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

  Widget _liveChip() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulse =
            0.45 + 0.55 * (0.5 + 0.5 * math.sin(_pulseCtrl.value * 2 * math.pi));
        return Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white.withValues(alpha: pulse * 0.65),
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
    final foreground = _locating ? _green : const Color(0xFF12200F);
    return GestureDetector(
      key: const Key('locate_button'),
      behavior: HitTestBehavior.opaque,
      onTap: _locating ? null : _locate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 56,
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
              : const Color(0xFF1E1E1E).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.55)
                : const Color(0xFF2C2C2C),
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
              color: active ? color : _muted,
              shadows: active
                  ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)]
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? color : _muted,
                fontSize: 16,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 1.2,
                shadows: active
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
    Widget corner({
      required bool top,
      required bool left,
    }) {
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

  Widget _telemetry(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 0.8,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
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
        shadows: glow
            ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 10)]
            : null,
      ),
    );
  }
}
