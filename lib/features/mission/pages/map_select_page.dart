import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/mission_service.dart';
import '../../../services/gps_location_service.dart';
import '../../../providers/weather_provider.dart';
import '../../../providers/preset_provider.dart';

class MapSelectPage extends ConsumerStatefulWidget {
  const MapSelectPage({super.key});

  @override
  ConsumerState<MapSelectPage> createState() => _MapSelectPageState();
}

class _MapSelectPageState extends ConsumerState<MapSelectPage> {
  final MapController _mapController = MapController();
  final List<LatLng> _waypoints = [];
  bool _isClosed = false;
  double? _area;
  bool _canClose = false;
  bool _isLocating = false;
  bool _showLabels = true;         // 是否显示地名标注（标准地图=有标注，卫星图=无标注）
  bool _isSatellite = true;        // 当前是否为卫星图模式

  // 默认上海坐标，GPS定位后会更新
  LatLng _center = const LatLng(31.2304, 121.4737);
  double _currentZoom = 16.0;
  static const double _minZoom = 3.0;
  static const double _maxZoom = 18.0;

  @override
  void initState() {
    super.initState();
    _autoLocate();
  }

  Future<void> _autoLocate() async {
    setState(() => _isLocating = true);
    final pos = await GpsLocationService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _center = LatLng(pos['lat']!, pos['lng']!);
        _isLocating = false;
      });
      _mapController.move(_center, 16.0);
    } else {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      final camera = _mapController.camera;
      setState(() {
        _currentZoom = camera.zoom;
        if (_waypoints.length >= 3 && !_isClosed) {
          final center = camera.center;
          final firstPoint = _waypoints.first;
          // 基于像素重叠检测：十字准心与第一个航点标记(20px)重叠
          // 将10px容差转换为地理坐标度数
          final pixelsPerDegree = (256 * pow(2, _currentZoom)) / 360;
          final closeThreshold = 10.0 / pixelsPerDegree; // 10px容差
          final distance = _calculateDistance(center, firstPoint);
          _canClose = distance < closeThreshold;
        } else {
          _canClose = false;
        }
      });
    }
  }

  double _calculateDistance(LatLng a, LatLng b) {
    return sqrt(pow(a.latitude - b.latitude, 2) + pow(a.longitude - b.longitude, 2));
  }

  void _addWaypoint() {
    final center = _mapController.camera.center;
    if (_canClose && _waypoints.length >= 3) {
      _closePolygon();
      return;
    }
    setState(() {
      _waypoints.add(center);
      _isClosed = false;
      _area = null;
      _canClose = false;
    });
  }

  void _closePolygon() {
    if (_waypoints.length < 3) return;
    setState(() {
      _isClosed = true;
      _area = MissionService.calculatePolygonAreaLatLng(_waypoints);
    });
    if (_area! < 0.5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该区域未达到无人机的最小作业范围'), duration: Duration(seconds: 3)),
      );
      setState(() {
        _isClosed = false;
        _waypoints.clear();
        _area = null;
      });
    }
  }

  void _undo() {
    if (_waypoints.isEmpty) return;
    setState(() {
      _waypoints.removeLast();
      _isClosed = false;
      _area = null;
      _canClose = false;
    });
  }

  void _finish() {
    if (_waypoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少添加3个航点')));
      return;
    }
    if (!_isClosed) {
      _closePolygon();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isClosed && _area != null && _area! >= 0.5) _navigateToTuning();
      });
      return;
    }
    _navigateToTuning();
  }

  void _navigateToTuning() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AiTuningPage(waypoints: _waypoints, area: _area!),
    ));
  }

  String _getMainButtonText() => (_canClose && _waypoints.length >= 3) ? '闭合区域' : '添加航点';
  IconData _getMainButtonIcon() => (_canClose && _waypoints.length >= 3) ? Icons.link : Icons.add_location_outlined;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('航点: ${_waypoints.length}${_isClosed ? " (已闭合)" : ""}'),
        actions: [
          if (_isLocating)
            const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          // 地名标注开关（仅卫星图模式下显示）
          if (_isSatellite)
            IconButton(
              icon: Icon(_showLabels ? Icons.location_on : Icons.location_on_outlined, color: _showLabels ? AppColors.primary : AppColors.textDisabled),
              onPressed: () => setState(() => _showLabels = !_showLabels),
              tooltip: _showLabels ? '隐藏地名' : '显示地名',
            ),
          // 图层切换按钮
          IconButton(
            icon: Icon(_isSatellite ? Icons.satellite_alt : Icons.map, color: AppColors.primary),
            onPressed: () => setState(() { _isSatellite = !_isSatellite; _showLabels = true; }),
            tooltip: _isSatellite ? '切换为标准地图' : '切换为卫星图',
          ),
          // 定位按钮
          IconButton(icon: const Icon(Icons.my_location), onPressed: _autoLocate, tooltip: '定位到当前位置'),
        ],
      ),
      body: Stack(
        children: [
          Container(
            color: const Color(0xFFE8E8E8),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _currentZoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                onMapEvent: _onMapEvent,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                // 图层：卫星图或标准地图（含地名路网）
                TileLayer(
                  urlTemplate: (_isSatellite && !_showLabels)
                      ? 'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}'
                      : 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                  subdomains: const ['1', '2', '3', '4'],
                  userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
                  maxZoom: _maxZoom,
                ),
                // 多边形填充
                if (_isClosed && _waypoints.length >= 3)
                  PolygonLayer(polygons: [
                    Polygon(points: _waypoints, color: AppColors.primary.withValues(alpha: 0.25), borderColor: AppColors.primary, borderStrokeWidth: 2, isFilled: true),
                  ]),
                // 航点连线
                if (_waypoints.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(points: [..._waypoints, if (_isClosed) _waypoints.first], color: Colors.red.shade700, strokeWidth: 2),
                  ]),
                // 第一个航点标记
                if (_waypoints.isNotEmpty)
                  MarkerLayer(markers: [
                    Marker(point: _waypoints.first, width: 24, height: 24, child: GestureDetector(
                      onTap: () => showModalBottomSheet(context: context, builder: (_) => Container(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('航点 1', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('纬度: ${_waypoints.first.latitude.toStringAsFixed(6)}'),
                        Text('经度: ${_waypoints.first.longitude.toStringAsFixed(6)}'),
                        const Padding(padding: EdgeInsets.only(top: 8), child: Text('起始航点', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
                      ]))),
                      child: Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.6), border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 3, offset: const Offset(0, 1))])),
                    )),
                  ]),
              ],
            ),
          ),
          // 十字准心
          const Positioned.fill(child: Center(child: _Crosshair())),
          // 比例尺（左下角）
          Positioned(bottom: 100, left: 12, child: _ScaleBar(zoom: _currentZoom, latitude: _center.latitude)),
          // 面积浮层
          if (_area != null && _isClosed)
            Positioned(top: MediaQuery.of(context).padding.top + kToolbarHeight + 12, left: 0, right: 0, child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.area_chart, color: Colors.white, size: 18), const SizedBox(width: 6),
                Text('面积: ${_area!.toStringAsFixed(1)} 亩', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
            ))),
          // 操作提示（修复溢出：使用Flexible包裹文本）
          if (_waypoints.isEmpty)
            Positioned(bottom: 100, left: 0, right: 0, child: Center(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Flexible(child: Text('移动地图使十字准心对准作业区域边缘，点击「添加航点」', style: TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ))),
          // 可闭合提示
          if (_canClose && !_isClosed)
            Positioned(top: MediaQuery.of(context).padding.top + kToolbarHeight + 60, left: 0, right: 0, child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.radio_button_checked, size: 16, color: Colors.white), SizedBox(width: 4),
                Flexible(child: Text('已对准起始航点，点击「闭合区域」完成圈选', style: TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ))),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_waypoints.isNotEmpty)
            Container(margin: const EdgeInsets.only(bottom: 8), constraints: const BoxConstraints(maxHeight: 60), child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _waypoints.length.clamp(0, 5), itemBuilder: (_, i) {
              final p = _waypoints[i];
              return Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: i == 0 ? AppColors.primary : AppColors.textDisabled.withValues(alpha: 0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 10, backgroundColor: i == 0 ? AppColors.primary : AppColors.error, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9))),
                const SizedBox(width: 6),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('航点${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}', style: TextStyle(fontSize: 9, color: AppColors.textDisabled)),
                ]),
              ]));
            })),
          Row(children: [
            if (_waypoints.isNotEmpty) ...[
              Expanded(child: OutlinedButton.icon(onPressed: _undo, icon: const Icon(Icons.undo, size: 18), label: const Text('撤销'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, padding: const EdgeInsets.symmetric(vertical: 14)))),
              const SizedBox(width: 10),
            ],
            Expanded(flex: 2, child: ElevatedButton.icon(onPressed: _isClosed ? null : _addWaypoint, icon: Icon(_getMainButtonIcon(), size: 20), label: Text(_getMainButtonText()), style: ElevatedButton.styleFrom(backgroundColor: _canClose ? AppColors.accent : AppColors.primary, foregroundColor: Colors.white, disabledBackgroundColor: AppColors.textDisabled.withValues(alpha: 0.3), padding: const EdgeInsets.symmetric(vertical: 14)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(onPressed: _waypoints.length >= 3 ? _finish : null, icon: const Icon(Icons.check, size: 18), label: const Text('完成'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDark, foregroundColor: Colors.white, disabledBackgroundColor: AppColors.textDisabled.withValues(alpha: 0.15), padding: const EdgeInsets.symmetric(vertical: 14)))),
          ]),
        ]),
      )),
    );
  }
}

/// 比例尺组件 - 根据缩放级别和纬度实时计算
class _ScaleBar extends StatelessWidget {
  final double zoom;
  final double latitude;
  const _ScaleBar({required this.zoom, required this.latitude});

  /// 计算每像素对应的地面距离(米)
  double _metersPerPixel() {
    const earthCircum = 40075016.686;
    return earthCircum * cos(latitude * pi / 180) / pow(2, zoom + 8);
  }

  /// 选择合适的比例尺长度（取整到最近的"漂亮"数字）
  ({double meters, double pixels}) _calcScale() {
    final mpp = _metersPerPixel();
    const targetPixels = 100.0;
    final rawMeters = mpp * targetPixels;

    // 取整到最近的漂亮数字
    final niceNumbers = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0];
    double bestMeters = niceNumbers.first;
    for (final n in niceNumbers) {
      if (n >= rawMeters) {
        bestMeters = n;
        break;
      }
      bestMeters = n;
    }
    return (meters: bestMeters, pixels: bestMeters / mpp);
  }

  String _formatMeters(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km';
    return '${m.toInt()} m';
  }

  @override
  Widget build(BuildContext context) {
    final scale = _calcScale();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_formatMeters(scale.meters), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 2),
        // 比例尺线
        Container(width: scale.pixels, height: 4, decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 1),
          color: const Color(0xFFCC0000),
        )),
      ]),
    );
  }
}

// ==================== 十字准心 ====================

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(width: 44, height: 44, child: CustomPaint(painter: _CrosshairPainter()));
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.red.shade600..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final cx = size.width / 2, cy = size.height / 2;
    const gap = 4.0;
    canvas.drawLine(Offset(cx, 0), Offset(cx, cy - gap), paint);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(cx - gap, cy), paint);
    canvas.drawLine(Offset(cx + gap, cy), Offset(size.width, cy), paint);
    final ringPaint = Paint()..color = Colors.red.shade600.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), 6, ringPaint);
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = Colors.red.shade700);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== AI调参页面 ====================

class AiTuningPage extends ConsumerStatefulWidget {
  final List<LatLng> waypoints;
  final double area;
  const AiTuningPage({super.key, required this.waypoints, required this.area});
  @override
  ConsumerState<AiTuningPage> createState() => _AiTuningPageState();
}

class _AiTuningPageState extends ConsumerState<AiTuningPage> {
  String _cropType = '水稻';
  String _operationType = '杀虫';
  double _flightHeight = 2.5, _flightSpeed = 5.0, _sprayVolume = 1.5, _sprayWidth = 6.0, _windCorrection = 0;
  bool _isAiLoading = true;
  final _cropTypes = ['水稻', '小麦', '玉米', '棉花', '果树', '蔬菜', '茶叶', '油菜'];
  final _operationTypes = ['杀虫', '除草', '施肥', '播种', '调节'];

  @override
  void initState() { super.initState(); _runAiTuning(); }

  Future<void> _runAiTuning() async {
    setState(() => _isAiLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final weather = ref.read(weatherProvider).valueOrNull;
    double windSpeed = weather?.windSpeed ?? 0;
    double height = 2.5, speed = 5.0, volume = 1.5, width = 6.0, correction = 0;
    switch (_cropType) {
      case '水稻': height = _operationType == '除草' ? 2.0 : 2.5; speed = 5.0; volume = _operationType == '除草' ? 2.0 : 1.5; break;
      case '小麦': height = 2.5; speed = 5.5; volume = 1.2; break;
      case '玉米': height = 3.0; speed = 4.5; volume = 1.8; break;
      case '棉花': height = 2.5; speed = 4.0; volume = 2.0; break;
      case '果树': height = 3.5; speed = 3.0; volume = 3.0; width = 4.0; break;
      case '蔬菜': height = 2.0; speed = 4.5; volume = 1.0; break;
      case '茶叶': height = 2.5; speed = 4.0; volume = 1.5; break;
      case '油菜': height = 2.5; speed = 5.0; volume = 1.5; break;
    }
    if (windSpeed > 5) { correction = (windSpeed * 2).clamp(-15.0, 15.0); speed = (speed * 0.9).clamp(2.0, 10.0); }
    if (!mounted) return;
    setState(() { _flightHeight = height; _flightSpeed = speed; _sprayVolume = volume; _sprayWidth = width; _windCorrection = correction; _isAiLoading = false; });
  }

  void _confirm() {
    final waypointMaps = widget.waypoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissionConfirmPage(
      waypoints: waypointMaps, area: widget.area, cropType: _cropType, operationType: _operationType,
      flightHeight: _flightHeight, flightSpeed: _flightSpeed, sprayVolume: _sprayVolume, sprayWidth: _sprayWidth, windCorrection: _windCorrection,
      referenceData: {'name': '${_cropType}${_operationType}方案', 'cropType': _cropType, 'operationType': _operationType, 'flightHeight': _flightHeight, 'flightSpeed': _flightSpeed, 'sprayVolume': _sprayVolume, 'sprayWidth': _sprayWidth, 'windCorrection': _windCorrection, 'isAiGenerated': true},
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI自动调参')),
      body: _isAiLoading ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('AI正在分析最佳参数...')]))
        : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildInfoCard(), const SizedBox(height: 16), _buildParamSelectors(), const SizedBox(height: 16), _buildSummary()])),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: ElevatedButton(onPressed: _confirm, child: const Text('确认参数，下一步')))),
    );
  }

  Widget _buildInfoCard() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('作业信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
    _buildDropdownRow('作物类型', _cropType, _cropTypes, (v) { setState(() => _cropType = v!); _runAiTuning(); }), const SizedBox(height: 8),
    _buildDropdownRow('作业类型', _operationType, _operationTypes, (v) { setState(() => _operationType = v!); _runAiTuning(); }), const SizedBox(height: 8),
    Row(children: [const Text('作业面积: ', style: TextStyle(color: AppColors.textSecondary)), Text('${widget.area.toStringAsFixed(1)} 亩', style: const TextStyle(fontWeight: FontWeight.w600)), const Spacer(), TextButton.icon(onPressed: _runAiTuning, icon: const Icon(Icons.auto_awesome, size: 16), label: const Text('重新分析'))]),
  ])));

  Widget _buildDropdownRow(String label, String value, List<String> items, ValueChanged<String?> onChanged) =>
    Row(children: [SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))), Expanded(child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged))]);

  Widget _buildParamSelectors() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('飞行参数', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
    _buildSlider('飞行高度', _flightHeight, 1.0, 10.0, 'm', (v) => setState(() => _flightHeight = v)),
    _buildSlider('飞行速度', _flightSpeed, 1.0, 15.0, 'm/s', (v) => setState(() => _flightSpeed = v)),
    _buildSlider('喷洒量', _sprayVolume, 0.5, 5.0, 'L/亩', (v) => setState(() => _sprayVolume = v)),
    _buildSlider('喷幅', _sprayWidth, 2.0, 10.0, 'm', (v) => setState(() => _sprayWidth = v)),
    _buildSlider('风速修正角', _windCorrection, -30, 30, '\u00B0', (v) => setState(() => _windCorrection = v)),
  ])));

  Widget _buildSlider(String label, double value, double min, double max, String unit, ValueChanged<double> onChanged) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)), Text('${value.toStringAsFixed(1)} $unit', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))]),
      Slider(value: value, min: min, max: max, divisions: ((max - min) * 10).toInt(), activeColor: AppColors.primary, onChanged: onChanged),
    ]);

  Widget _buildSummary() {
    final time = MissionService.estimateTime(widget.area, _flightSpeed, _sprayWidth);
    final medicine = MissionService.estimateMedicine(widget.area, _sprayVolume);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('预估信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 12),
      _summaryRow('预计时间', time), _summaryRow('预计用药', '$medicine L'), _summaryRow('预计飞行距离', '${(widget.area * 666.67 / (_sprayWidth * 0.8)).toStringAsFixed(0)} m'),
    ])));
  }

  Widget _summaryRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: AppColors.textSecondary)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))]));
}

// ==================== 任务确认页面 ====================

class MissionConfirmPage extends ConsumerStatefulWidget {
  final List<Map<String, double>> waypoints;
  final double area;
  final String cropType, operationType;
  final double flightHeight, flightSpeed, sprayVolume, sprayWidth, windCorrection;
  final Map<String, dynamic> referenceData;
  const MissionConfirmPage({super.key, required this.waypoints, required this.area, required this.cropType, required this.operationType, required this.flightHeight, required this.flightSpeed, required this.sprayVolume, required this.sprayWidth, required this.windCorrection, required this.referenceData});
  @override
  ConsumerState<MissionConfirmPage> createState() => _MissionConfirmPageState();
}

class _MissionConfirmPageState extends ConsumerState<MissionConfirmPage> {
  bool _saveAsPreset = false;
  String _presetName = '';
  @override
  void initState() { super.initState(); _presetName = '${widget.cropType}${widget.operationType}方案'; }

  void _submit() {
    ref.read(presetsProvider.notifier).addPreset(widget.referenceData);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任务已创建，等待连接设备后开始作业')));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final time = MissionService.estimateTime(widget.area, widget.flightSpeed, widget.sprayWidth);
    final medicine = MissionService.estimateMedicine(widget.area, widget.sprayVolume);
    return Scaffold(appBar: AppBar(title: const Text('参数确认')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('作业参数汇总', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Divider(height: 24),
        _paramRow('作物类型', widget.cropType), _paramRow('作业类型', widget.operationType), _paramRow('作业面积', '${widget.area.toStringAsFixed(1)} 亩'), _paramRow('航点数量', '${widget.waypoints.length} 个'),
        _paramRow('飞行高度', '${widget.flightHeight.toStringAsFixed(1)} m'), _paramRow('飞行速度', '${widget.flightSpeed.toStringAsFixed(1)} m/s'), _paramRow('喷洒量', '${widget.sprayVolume.toStringAsFixed(1)} L/亩'), _paramRow('喷幅', '${widget.sprayWidth.toStringAsFixed(1)} m'), _paramRow('风速修正角', '${widget.windCorrection.toStringAsFixed(1)}\u00B0'),
        const Divider(height: 24), _paramRow('预计时间', time), _paramRow('预计用药', '$medicine L'),
      ]))),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(title: const Text('保存为预设'), subtitle: const Text('下次可直接使用此参数'), value: _saveAsPreset, activeColor: AppColors.primary, onChanged: (v) => setState(() => _saveAsPreset = v), contentPadding: EdgeInsets.zero),
        if (_saveAsPreset) TextField(decoration: const InputDecoration(labelText: '预设名称', hintText: '输入预设名称...'), controller: TextEditingController(text: _presetName), onChanged: (v) => _presetName = v),
      ]))),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('提交任务', style: TextStyle(fontSize: 18)))),
    ])));
  }
  Widget _paramRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: AppColors.textSecondary)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))]));
}