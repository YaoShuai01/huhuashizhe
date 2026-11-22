import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/cloud_models.dart';

const String _satelliteUrl =
    'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}';

List<LatLng> latLngsOf(List<List<double>> points) =>
    points.map((p) => LatLng(p[0], p[1])).toList();

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

class CloudFarmMap extends StatelessWidget {
  final List<CloudPlot> plots;
  final String? selectedId;
  final ValueChanged<String>? onSelectPlot;
  final ValueChanged<List<double>>? onAddPoint;
  final List<List<double>> drawPoints;
  final LatLng? center;
  final double zoom;
  final MapController? mapController;

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
  });

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>[];
    for (final plot in plots) {
      if (plot.polygon.length < 3) continue;
      final active = plot.id == selectedId;
      polygons.add(Polygon(
        points: latLngsOf(plot.polygon),
        color: (active ? const Color(0xFFFFD166) : const Color(0xFF6ED37C))
            .withValues(alpha: active ? 0.26 : 0.16),
        borderColor: active ? const Color(0xFFFFD166) : const Color(0xFF8FE39A),
        borderStrokeWidth: active ? 3 : 2,
      ));
    }

    final drawPolygons = <Polygon>[];
    if (drawPoints.length >= 3) {
      drawPolygons.add(Polygon(
        points: latLngsOf(drawPoints),
        color: const Color(0xFF6ED37C).withValues(alpha: 0.22),
        borderColor: const Color(0xFF8FE39A),
        borderStrokeWidth: 2.5,
      ));
    } else if (drawPoints.length == 2) {
      drawPolygons.add(Polygon(
        points: latLngsOf(drawPoints),
        color: Colors.transparent,
        borderColor: const Color(0xFF8FE39A),
        borderStrokeWidth: 2,
      ));
    }

    final markers = <Marker>[];
    for (final plot in plots) {
      if (plot.polygon.length < 3) continue;
      markers.add(Marker(
        point: centroidOf(plot.polygon),
        width: 120,
        height: 26,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2A1E).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Text(
                '${plot.name} · ${plot.area.toStringAsFixed(1)}亩',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ),
      ));
    }
    for (final p in drawPoints) {
      markers.add(Marker(
        point: LatLng(p[0], p[1]),
        width: 14,
        height: 14,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E7D32), width: 3),
          ),
        ),
      ));
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center ?? LatLng(CloudSeed.region.lat, CloudSeed.region.lng),
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: (tapPosition, point) {
          if (onAddPoint != null) {
            onAddPoint!([point.latitude, point.longitude]);
            return;
          }
          if (onSelectPlot == null) return;
          for (var i = plots.length - 1; i >= 0; i--) {
            final plot = plots[i];
            if (plot.polygon.length >= 3 &&
                _pointInPolygon(point.latitude, point.longitude, plot.polygon)) {
              onSelectPlot!(plot.id);
              return;
            }
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _satelliteUrl,
          subdomains: const ['1', '2', '3', '4'],
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
              point: center ?? LatLng(CloudSeed.region.lat, CloudSeed.region.lng),
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
    );
  }
}

/// 只读小地图（田块实景 / 巡检画面）
class MiniPlotMap extends StatelessWidget {
  final List<List<double>> polygon;
  final double zoom;
  final BorderRadius? borderRadius;

  const MiniPlotMap({
    super.key,
    required this.polygon,
    this.zoom = 17,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final points = latLngsOf(polygon);
    final center = polygon.isEmpty ? const LatLng(30.4072, 112.1359) : centroidOf(polygon);
    final content = FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: _satelliteUrl,
          subdomains: const ['1', '2', '3', '4'],
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
