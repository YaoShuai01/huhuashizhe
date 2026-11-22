import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/coord_transform.dart';
import '../models/cloud_models.dart';

const String _satelliteUrl =
    'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}';

/// 国内地图注记层（道路 + 地名），与卫星图同为 GCJ-02 瓦片
const String _annotationUrl =
    'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}';

const List<String> _amapSubdomains = ['1', '2', '3', '4'];

List<LatLng> latLngsOf(List<List<double>> points) =>
    points.map((p) => LatLng(p[0], p[1])).toList();

/// 存储坐标（WGS-84，GPS 原始值）→ 显示坐标（GCJ-02，国内地图瓦片）
LatLng displayPoint(double lat, double lng) =>
    CoordTransform.wgs84ToGcj02(lat, lng);

/// 批量把存储坐标转为国内地图瓦片坐标系
List<LatLng> displayLatLngsOf(List<List<double>> points) =>
    points.map((p) => displayPoint(p[0], p[1])).toList();

/// 显示坐标（GCJ-02）→ 存储坐标（WGS-84）
List<double> storagePoint(LatLng point) {
  final wgs = CoordTransform.gcj02ToWgs84(point.latitude, point.longitude);
  return [wgs.latitude, wgs.longitude];
}

LatLng centroidOf(List<List<double>> points) {
  if (points.isEmpty) return const LatLng(30.4072, 112.1359);
  final lat = points.fold<double>(0, (s, p) => s + p[0]) / points.length;
  final lng = points.fold<double>(0, (s, p) => s + p[1]) / points.length;
  return LatLng(lat, lng);
}

bool _pointInPolygon(double lat, double lng, List<List<double>> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final yi = poly[i][0], xi = poly[i][1];
    final yj = poly[j][0], xj = poly[j][1];
    final intersect = ((yi > lat) != (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

class CloudFarmMap extends StatefulWidget {
  final List<CloudPlot> plots;
  final String? selectedId;
  final ValueChanged<String>? onSelectPlot;
  final ValueChanged<List<double>>? onAddPoint;
  final List<List<double>> drawPoints;
  final LatLng? center;
  final double zoom;
  final MapController? mapController;

  /// 首次渲染时的取景范围（用于自动框住全部田块）
  final CameraFit? cameraFit;

  /// 地图首次就绪回调
  final VoidCallback? onMapReady;

  /// 缩放级别变化回调（用于比例尺）
  final ValueChanged<double>? onZoomChanged;

  /// 是否叠加国内地图注记层（道路与地名）
  final bool showLabels;

  /// 拖动已选边界点回调（index, 新的 [lat, lng]）
  final void Function(int index, List<double> point)? onMovePoint;

  const CloudFarmMap({
    super.key,
    required this.plots,
    this.selectedId,
    this.onSelectPlot,
    this.onAddPoint,
    this.drawPoints = const [],
    this.center,
    this.zoom = 16,
    this.mapController,
    this.cameraFit,
    this.onMapReady,
    this.onZoomChanged,
    this.showLabels = true,
    this.onMovePoint,
  });

  @override
  State<CloudFarmMap> createState() => _CloudFarmMapState();
}

class _CloudFarmMapState extends State<CloudFarmMap> {
  /// 顶点命中半径（dp）
  static const double _hitRadius = 24;

  final MapController _internalController = MapController();
  int? _dragIndex;
  int? _dragPointer;
  bool _suppressTap = false;

  MapController get _controller => widget.mapController ?? _internalController;

  /// 命中最近的已选顶点，未命中返回 null
  int? _hitTestVertex(Offset localPosition) {
    final camera = _controller.camera;
    int? best;
    var bestDistance = _hitRadius;
    for (var i = 0; i < widget.drawPoints.length; i++) {
      final p = widget.drawPoints[i];
      final screen = camera.latLngToScreenPoint(displayPoint(p[0], p[1]));
      final distance = (Offset(screen.x, screen.y) - localPosition).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  void _handlePointerDown(PointerDownEvent event) {
    // 拖动中忽略其它手指，避免打断当前顶点
    if (_dragIndex != null) return;
    _suppressTap = false;
    if (widget.onMovePoint == null || widget.drawPoints.isEmpty) return;
    final index = _hitTestVertex(event.localPosition);
    if (index == null) return;
    // 命中顶点：进入拖动态，禁止本次手势同时拖动地图/新增点
    _suppressTap = true;
    _dragPointer = event.pointer;
    setState(() => _dragIndex = index);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final index = _dragIndex;
    if (index == null || event.pointer != _dragPointer) return;
    if (index >= widget.drawPoints.length) return;
    final latLng = _controller.camera.offsetToCrs(event.localPosition);
    widget.onMovePoint!(index, storagePoint(latLng));
  }

  void _endDrag([PointerEvent? event]) {
    if (_dragIndex == null) return;
    if (event != null && event.pointer != _dragPointer) return;
    setState(() {
      _dragIndex = null;
      _dragPointer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>[];
    for (final plot in widget.plots) {
      if (plot.polygon.length < 3) continue;
      final active = plot.id == widget.selectedId;
      polygons.add(Polygon(
        points: displayLatLngsOf(plot.polygon),
        color: (active ? const Color(0xFFFFD166) : const Color(0xFF6ED37C))
            .withValues(alpha: active ? 0.32 : 0.20),
        borderColor: active ? const Color(0xFFFFD166) : const Color(0xFF9BE7A4),
        borderStrokeWidth: active ? 3.5 : 2,
        pattern: active
            ? const StrokePattern.solid()
            : StrokePattern.dashed(segments: const [6, 4]),
      ));
    }

    final drawPolygons = <Polygon>[];
    if (widget.drawPoints.length >= 3) {
      drawPolygons.add(Polygon(
        points: displayLatLngsOf(widget.drawPoints),
        color: const Color(0xFF6ED37C).withValues(alpha: 0.22),
        borderColor: const Color(0xFF8FE39A),
        borderStrokeWidth: 2.5,
      ));
    } else if (widget.drawPoints.length == 2) {
      drawPolygons.add(Polygon(
        points: displayLatLngsOf(widget.drawPoints),
        color: Colors.transparent,
        borderColor: const Color(0xFF8FE39A),
        borderStrokeWidth: 2,
      ));
    }

    final markers = <Marker>[];
    for (final plot in widget.plots) {
      if (plot.polygon.length < 3) continue;
      final active = plot.id == widget.selectedId;
      markers.add(Marker(
        point: displayPoint(
          centroidOf(plot.polygon).latitude,
          centroidOf(plot.polygon).longitude,
        ),
        width: 150,
        height: 28,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2A1E).withValues(alpha: active ? 0.88 : 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? const Color(0xFFFFD166)
                      : Colors.white.withValues(alpha: 0.35),
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Text(
                '${plot.name} · ${plot.area.toStringAsFixed(1)}亩',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? const Color(0xFFFFE6A3) : Colors.white,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ));
    }
    for (var i = 0; i < widget.drawPoints.length; i++) {
      final p = widget.drawPoints[i];
      final dragging = _dragIndex == i;
      markers.add(Marker(
        point: displayPoint(p[0], p[1]),
        width: 30,
        height: 30,
        child: IgnorePointer(
          child: Center(
            child: Container(
              width: dragging ? 28 : 18,
              height: dragging ? 28 : 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dragging
                    ? Colors.white.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.20),
                shape: BoxShape.circle,
                border: Border.all(
                  color: dragging ? Colors.white : const Color(0xFF8FE39A),
                  width: dragging ? 2.2 : 1.2,
                ),
              ),
              child: Container(
                width: dragging ? 13 : 10,
                height: dragging ? 13 : 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2E7D32), width: 2.5),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    final flags = _dragIndex == null
        ? InteractiveFlag.all & ~InteractiveFlag.rotate
        : InteractiveFlag.all &
            ~InteractiveFlag.rotate &
            ~InteractiveFlag.drag;

    return Listener(
      onPointerMove: _handlePointerMove,
      child: FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: widget.center != null
              ? displayPoint(widget.center!.latitude, widget.center!.longitude)
              : displayPoint(CloudSeed.region.lat, CloudSeed.region.lng),
          initialZoom: widget.zoom,
          initialCameraFit: widget.cameraFit,
          minZoom: 3,
          maxZoom: 19,
          onMapReady: widget.onMapReady,
          onPositionChanged: widget.onZoomChanged == null
              ? null
              : (camera, hasGesture) => widget.onZoomChanged!(camera.zoom),
          interactionOptions: InteractionOptions(flags: flags),
          onPointerDown: (event, point) => _handlePointerDown(event),
          onPointerUp: (event, point) => _endDrag(event),
          onPointerCancel: (event, point) => _endDrag(event),
          onTap: (tapPosition, point) {
            if (_suppressTap) {
              _suppressTap = false;
              return;
            }
            if (widget.onAddPoint != null) {
              widget.onAddPoint!(storagePoint(point));
              return;
            }
            if (widget.onSelectPlot == null) return;
            final stored = storagePoint(point);
            for (var i = widget.plots.length - 1; i >= 0; i--) {
              final plot = widget.plots[i];
              if (plot.polygon.length >= 3 &&
                  _pointInPolygon(stored[0], stored[1], plot.polygon)) {
                widget.onSelectPlot!(plot.id);
                return;
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: _satelliteUrl,
            subdomains: _amapSubdomains,
            userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
            maxZoom: 19,
          ),
          // 注记层加载失败只影响道路/地名，不影响卫星底图与多边形
          if (widget.showLabels)
            TileLayer(
              urlTemplate: _annotationUrl,
              subdomains: _amapSubdomains,
              userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
              maxZoom: 19,
            ),
          if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
          if (drawPolygons.isNotEmpty) PolygonLayer(polygons: drawPolygons),
          if (markers.isNotEmpty)
            MarkerLayer(markers: markers)
          else
            MarkerLayer(markers: [
              Marker(
                point: widget.center != null
                    ? displayPoint(
                        widget.center!.latitude, widget.center!.longitude)
                    : displayPoint(CloudSeed.region.lat, CloudSeed.region.lng),
                width: 16,
                height: 16,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

/// 只读小地图（田块实景 / 巡检画面）
class MiniPlotMap extends StatelessWidget {
  final List<List<double>> polygon;
  final double zoom;
  final BorderRadius? borderRadius;

  /// 是否叠加国内地图注记层（道路与地名）
  final bool showLabels;

  const MiniPlotMap({
    super.key,
    required this.polygon,
    this.zoom = 17,
    this.borderRadius,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final points = displayLatLngsOf(polygon);
    final center = polygon.isEmpty
        ? displayPoint(30.4072, 112.1359)
        : displayPoint(centroidOf(polygon).latitude, centroidOf(polygon).longitude);
    final content = FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: _satelliteUrl,
          subdomains: _amapSubdomains,
          userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
          maxZoom: 19,
        ),
        if (showLabels)
          TileLayer(
            urlTemplate: _annotationUrl,
            subdomains: _amapSubdomains,
            userAgentPackageName: 'com.huhuashizhe.huhuashizhe',
            maxZoom: 19,
          ),
        if (points.length >= 3)
          PolygonLayer(polygons: [
            Polygon(
              points: points,
              color: const Color(0xFF6ED37C).withValues(alpha: 0.18),
              borderColor: const Color(0xFFFFD166),
              borderStrokeWidth: 2.5,
            ),
          ]),
      ],
    );
    final radius = borderRadius ?? BorderRadius.circular(12);
    return ClipRRect(borderRadius: radius, child: content);
  }
}

/// 地图尺寸工具
class MapMetrics {
  static double areaMu(List<List<double>> points) {
    if (points.length < 3) return 0;
    final lat0 = points.fold<double>(0, (s, p) => s + p[0]) /
        points.length *
        math.pi /
        180;
    const r = 6378137.0;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final x1 = a[1] * math.pi / 180 * r * math.cos(lat0);
      final y1 = a[0] * math.pi / 180 * r;
      final x2 = b[1] * math.pi / 180 * r * math.cos(lat0);
      final y2 = b[0] * math.pi / 180 * r;
      sum += x1 * y2 - x2 * y1;
    }
    return (sum / 2).abs() / 666.6667;
  }
}
