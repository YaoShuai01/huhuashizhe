import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/mission_service.dart';
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

  // 默认定位到上海（后续接入GPS后自动定位）
  static const LatLng _defaultCenter = LatLng(31.2304, 121.4737);
  double _currentZoom = 16.0;

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      final camera = _mapController.camera;
      setState(() {
        _currentZoom = camera.zoom;
        // 检查十字准心是否接近第一个航点 → 显示"闭合区域"
        if (_waypoints.length >= 3 && !_isClosed) {
          final center = camera.center;
          final firstPoint = _waypoints.first;
          const closeThreshold = 0.0005; // 约50米
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
    // 获取地图中心点（十字准心位置）作为航点
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

    // 将第一个航点再次添加以闭合多边形
    setState(() {
      _isClosed = true;
      _area = MissionService.calculatePolygonAreaLatLng(_waypoints);
    });

    if (_area! < 0.5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该区域未达到无人机的最小作业范围'),
          duration: Duration(seconds: 3),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少添加3个航点')),
      );
      return;
    }
    if (!_isClosed) {
      _closePolygon();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isClosed && _area != null && _area! >= 0.5) {
          _navigateToTuning();
        }
      });
      return;
    }
    _navigateToTuning();
  }

  void _navigateToTuning() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiTuningPage(
          waypoints: _waypoints,
          area: _area!,
        ),
      ),
    );
  }

  void _locateMe() {
    _mapController.move(_defaultCenter, 17.0);
  }

  String _getMainButtonText() {
    if (_canClose && _waypoints.length >= 3) return '闭合区域';
    return '添加航点';
  }

  IconData _getMainButtonIcon() {
    if (_canClose && _waypoints.length >= 3) return Icons.link;
    return Icons.add_location_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('航点: ${_waypoints.length}${_isClosed ? " (已闭合)" : ""}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _locateMe,
            tooltip: '定位到当前位置',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () {},
            tooltip: '切换地图类型',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 地图主体
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _currentZoom,
              onMapEvent: _onMapEvent,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
                maxZoom: 19,
              ),

              // 多边形填充（闭合后显示浅蓝色）
              if (_isClosed && _waypoints.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _waypoints,
                      color: AppColors.primary.withValues(alpha: 0.25),
                      borderColor: AppColors.primary,
                      borderStrokeWidth: 2,
                      isFilled: true,
                    ),
                  ],
                ),

              // 航点连线
              if (_waypoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [..._waypoints, if (_isClosed) _waypoints.first],
                      color: Colors.red.shade700,
                      strokeWidth: 2,
                    ),
                  ],
                ),

              // 航点标记
                  MarkerLayer(
                    markers: _waypoints.asMap().entries.map((entry) {
                      final index = entry.key;
                      final point = entry.value;
                      return Marker(
                        point: point,
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () {
                            // 点击航点可查看信息
                            showModalBottomSheet(
                              context: context,
                              builder: (ctx) => Container(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('航点 ${index + 1}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text('纬度: ${point.latitude.toStringAsFixed(6)}'),
                                    Text('经度: ${point.longitude.toStringAsFixed(6)}'),
                                    if (index == 0)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text('起始航点',
                                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 红色圆点
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index == 0 ? AppColors.primary : Colors.red.shade600,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              // 序号文字
                              Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

              // 十字准心（始终在屏幕中央）
              const Center(
                child: _Crosshair(),
              ),
            ],
          ),

          // 面积显示浮层
          if (_area != null && _isClosed)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.area_chart, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '面积: ${_area!.toStringAsFixed(1)} 亩',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 操作提示浮层
          if (_waypoints.isEmpty)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '移动地图使十字准心对准作业区域边缘，点击「添加航点」',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 可闭合提示
          if (_canClose && !_isClosed)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radio_button_checked, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text('已对准起始航点，点击「闭合区域」完成圈选',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),

      // 底部操作栏
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 航点列表预览（最多显示最近3个）
              if (_waypoints.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: const BoxConstraints(maxHeight: 60),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _waypoints.length.clamp(0, 5),
                    itemBuilder: (context, index) {
                      final p = _waypoints[index];
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: index == 0 ? AppColors.primary : AppColors.textDisabled.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: index == 0 ? AppColors.primary : AppColors.error,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 9),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('航点${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text('${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}',
                                    style: TextStyle(fontSize: 9, color: AppColors.textDisabled)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              // 按钮行
              Row(
                children: [
                  // 撤销按钮
                  if (_waypoints.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('撤销'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  if (_waypoints.isNotEmpty) const SizedBox(width: 10),

                  // 主操作按钮：添加航点 / 闭合区域
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isClosed ? null : _addWaypoint,
                      icon: Icon(_getMainButtonIcon(), size: 20),
                      label: Text(_getMainButtonText()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canClose ? AppColors.accent : AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.textDisabled.withValues(alpha: 0.3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 完成按钮
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _waypoints.length >= 3 ? _finish : null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('完成'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.textDisabled.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 十字准心组件 - 始终显示在地图中心
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _CrosshairPainter(),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.shade600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    const len = 10.0; // 十字线长度
    const gap = 4.0; // 中心间隙

    // 上
    canvas.drawLine(Offset(cx, 0), Offset(cx, cy - gap), paint);
    // 下
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, size.height), paint);
    // 左
    canvas.drawLine(Offset(0, cy), Offset(cx - gap, cy), paint);
    // 右
    canvas.drawLine(Offset(cx + gap, cy), Offset(size.width, cy), paint);

    // 中心圆环
    final ringPaint = Paint()
      ..color = Colors.red.shade600.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), 6, ringPaint);

    // 中心点
    final dotPaint = Paint()..color = Colors.red.shade700;
    canvas.drawCircle(Offset(cx, cy), 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==================== AI调参页面 ====================

class AiTuningPage extends ConsumerStatefulWidget {
  final List<LatLng> waypoints;
  final double area;

  const AiTuningPage({
    super.key,
    required this.waypoints,
    required this.area,
  });

  @override
  ConsumerState<AiTuningPage> createState() => _AiTuningPageState();
}

class _AiTuningPageState extends ConsumerState<AiTuningPage> {
  String _cropType = '水稻';
  String _operationType = '杀虫';
  double _flightHeight = 2.5;
  double _flightSpeed = 5.0;
  double _sprayVolume = 1.5;
  double _sprayWidth = 6.0;
  double _windCorrection = 0;
  bool _isAiLoading = true;

  final _cropTypes = ['水稻', '小麦', '玉米', '棉花', '果树', '蔬菜', '茶叶', '油菜'];
  final _operationTypes = ['杀虫', '除草', '施肥', '播种', '调节'];

  @override
  void initState() {
    super.initState();
    _runAiTuning();
  }

  Future<void> _runAiTuning() async {
    setState(() => _isAiLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    final weather = ref.read(weatherProvider).valueOrNull;
    double windSpeed = weather?.windSpeed ?? 0;

    double height = 2.5;
    double speed = 5.0;
    double volume = 1.5;
    double width = 6.0;
    double correction = 0;

    switch (_cropType) {
      case '水稻':
        height = _operationType == '除草' ? 2.0 : 2.5;
        speed = 5.0;
        volume = _operationType == '除草' ? 2.0 : 1.5;
        break;
      case '小麦':
        height = 2.5; speed = 5.5; volume = 1.2;
        break;
      case '玉米':
        height = 3.0; speed = 4.5; volume = 1.8;
        break;
      case '棉花':
        height = 2.5; speed = 4.0; volume = 2.0;
        break;
      case '果树':
        height = 3.5; speed = 3.0; volume = 3.0; width = 4.0;
        break;
      case '蔬菜':
        height = 2.0; speed = 4.5; volume = 1.0;
        break;
      case '茶叶':
        height = 2.5; speed = 4.0; volume = 1.5;
        break;
      case '油菜':
        height = 2.5; speed = 5.0; volume = 1.5;
        break;
    }

    if (windSpeed > 5) {
      correction = (windSpeed * 2).clamp(-15.0, 15.0);
      speed = (speed * 0.9).clamp(2.0, 10.0);
    }

    if (!mounted) return;
    setState(() {
      _flightHeight = height;
      _flightSpeed = speed;
      _sprayVolume = volume;
      _sprayWidth = width;
      _windCorrection = correction;
      _isAiLoading = false;
    });
  }

  void _confirm() {
    // 将LatLng转换为Map格式传递
    final waypointMaps = widget.waypoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MissionConfirmPage(
          waypoints: waypointMaps,
          area: widget.area,
          cropType: _cropType,
          operationType: _operationType,
          flightHeight: _flightHeight,
          flightSpeed: _flightSpeed,
          sprayVolume: _sprayVolume,
          sprayWidth: _sprayWidth,
          windCorrection: _windCorrection,
          referenceData: {
            'name': '${_cropType}${_operationType}方案',
            'cropType': _cropType,
            'operationType': _operationType,
            'flightHeight': _flightHeight,
            'flightSpeed': _flightSpeed,
            'sprayVolume': _sprayVolume,
            'sprayWidth': _sprayWidth,
            'windCorrection': _windCorrection,
            'isAiGenerated': true,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI自动调参')),
      body: _isAiLoading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('AI正在分析最佳参数...')]))
          : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildInfoCard(), const SizedBox(height: 16), _buildParamSelectors(), const SizedBox(height: 16), _buildSummary()])),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: ElevatedButton(onPressed: _confirm, child: const Text('确认参数，下一步')))),
    );
  }

  Widget _buildInfoCard() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('作业信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _buildDropdownRow('作物类型', _cropType, _cropTypes, (v) { setState(() => _cropType = v!); _runAiTuning(); }),
      const SizedBox(height: 8),
      _buildDropdownRow('作业类型', _operationType, _operationTypes, (v) { setState(() => _operationType = v!); _runAiTuning(); }),
      const SizedBox(height: 8),
      Row(children: [
        const Text('作业面积: ', style: TextStyle(color: AppColors.textSecondary)),
        Text('${widget.area.toStringAsFixed(1)} 亩', style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(onPressed: _runAiTuning, icon: const Icon(Icons.auto_awesome, size: 16), label: const Text('重新分析')),
      ]),
    ])));
  }

  Widget _buildDropdownRow(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
      Expanded(child: DropdownButtonFormField<String>(value: value, isExpanded: true, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true), items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onChanged)),
    ]);
  }

  Widget _buildParamSelectors() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('飞行参数', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _buildSlider('飞行高度', _flightHeight, 1.0, 10.0, 'm', (v) => setState(() => _flightHeight = v)),
      _buildSlider('飞行速度', _flightSpeed, 1.0, 15.0, 'm/s', (v) => setState(() => _flightSpeed = v)),
      _buildSlider('喷洒量', _sprayVolume, 0.5, 5.0, 'L/亩', (v) => setState(() => _sprayVolume = v)),
      _buildSlider('喷幅', _sprayWidth, 2.0, 10.0, 'm', (v) => setState(() => _sprayWidth = v)),
      _buildSlider('风速修正角', _windCorrection, -30, 30, '\u00B0', (v) => setState(() => _windCorrection = v)),
    ])));
  }

  Widget _buildSlider(String label, double value, double min, double max, String unit, ValueChanged<double> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text('${value.toStringAsFixed(1)} $unit', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
      Slider(value: value, min: min, max: max, divisions: ((max - min) * 10).toInt(), activeColor: AppColors.primary, onChanged: onChanged),
    ]);
  }

  Widget _buildSummary() {
    final time = MissionService.estimateTime(widget.area, _flightSpeed, _sprayWidth);
    final medicine = MissionService.estimateMedicine(widget.area, _sprayVolume);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('预估信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _summaryRow('预计时间', time),
      _summaryRow('预计用药', '$medicine L'),
      _summaryRow('预计飞行距离', '${(widget.area * 666.67 / (_sprayWidth * 0.8)).toStringAsFixed(0)} m'),
    ])));
  }

  Widget _summaryRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    ]));
  }
}

// ==================== 任务确认页面 ====================

class MissionConfirmPage extends ConsumerStatefulWidget {
  final List<Map<String, double>> waypoints;
  final double area;
  final String cropType;
  final String operationType;
  final double flightHeight;
  final double flightSpeed;
  final double sprayVolume;
  final double sprayWidth;
  final double windCorrection;
  final Map<String, dynamic> referenceData;

  const MissionConfirmPage({
    super.key,
    required this.waypoints,
    required this.area,
    required this.cropType,
    required this.operationType,
    required this.flightHeight,
    required this.flightSpeed,
    required this.sprayVolume,
    required this.sprayWidth,
    required this.windCorrection,
    required this.referenceData,
  });

  @override
  ConsumerState<MissionConfirmPage> createState() => _MissionConfirmPageState();
}

class _MissionConfirmPageState extends ConsumerState<MissionConfirmPage> {
  bool _saveAsPreset = false;
  String _presetName = '';

  @override
  void initState() {
    super.initState();
    _presetName = '${widget.cropType}${widget.operationType}方案';
  }

  void _submit() {
    ref.read(presetsProvider.notifier).addPreset(widget.referenceData);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u4efb\u52a1\u5df2\u521b\u5efa\uff0c\u7b49\u5f85\u8fde\u63a5\u8bbe\u5907\u540e\u5f00\u59cb\u4f5c\u4e1a')));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final time = MissionService.estimateTime(widget.area, widget.flightSpeed, widget.sprayWidth);
    final medicine = MissionService.estimateMedicine(widget.area, widget.sprayVolume);

    return Scaffold(appBar: AppBar(title: const Text('\u53c2\u6570\u786e\u8ba4')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('\u4f5c\u4e1a\u53c2\u6570\u6c47\u603b', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(height: 24),
        _paramRow('\u4f5c\u7269\u7c7b\u578b', widget.cropType),
        _paramRow('\u4f5c\u4e1a\u7c7b\u578b', widget.operationType),
        _paramRow('\u4f5c\u4e1a\u9762\u79ef', '${widget.area.toStringAsFixed(1)} \u4ea9'),
        _paramRow('\u822a\u70b9\u6570\u91cf', '${widget.waypoints.length} \u4e2a'),
        _paramRow('\u98de\u884c\u9ad8\u5ea6', '${widget.flightHeight.toStringAsFixed(1)} m'),
        _paramRow('\u98de\u884c\u901f\u5ea6', '${widget.flightSpeed.toStringAsFixed(1)} m/s'),
        _paramRow('\u55b7\u6d12\u91cf', '${widget.sprayVolume.toStringAsFixed(1)} L/\u4ea9'),
        _paramRow('\u55b7\u5e45', '${widget.sprayWidth.toStringAsFixed(1)} m'),
        _paramRow('\u98ce\u901f\u4fee\u6b63\u89d2', '${widget.windCorrection.toStringAsFixed(1)}\u00B0'),
        const Divider(height: 24),
        _paramRow('\u9884\u8ba1\u65f6\u95f4', time),
        _paramRow('\u9884\u8ba1\u7528\u836f', '$medicine L'),
      ]))),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(title: const Text('\u4fdd\u5b58\u4e3a\u9884\u8bbe'), subtitle: const Text('\u4e0b\u6b21\u53ef\u76f4\u63a5\u4f7f\u7528\u6b64\u53c2\u6570'), value: _saveAsPreset, activeColor: AppColors.primary, onChanged: (v) => setState(() => _saveAsPreset = v), contentPadding: EdgeInsets.zero),
        if (_saveAsPreset) TextField(decoration: const InputDecoration(labelText: '\u9884\u8bbe\u540d\u79f0', hintText: '\u8f93\u5165\u9884\u8bbe\u540d\u79f0...'), controller: TextEditingController(text: _presetName), onChanged: (v) => _presetName = v),
      ]))),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('\u63d0\u4ea4\u4efb\u52a1', style: TextStyle(fontSize: 18)))),
    ])));
  }

  Widget _paramRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    ]));
  }
}
