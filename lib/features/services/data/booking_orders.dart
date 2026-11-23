import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/local_database.dart';

/// 农户预约飞防订单：农户提交后同步到飞手工作台
class BookingOrder {
  const BookingOrder({
    required this.id,
    required this.crop,
    required this.area,
    required this.unitPrice,
    required this.address,
    required this.time,
    required this.pilotName,
    required this.contactName,
    required this.phone,
    required this.createdAt,
    this.note = '',
    this.accepted = false,
    this.acceptedAt,
  });

  final String id;
  final String crop;

  /// 作业面积（亩）
  final double area;

  /// 按亩单价（元/亩）
  final double unitPrice;
  final String address;

  /// 作业时间，如「2026年11月24日 上午」
  final String time;

  /// 农户指定的飞手
  final String pilotName;
  final String contactName;
  final String phone;
  final String note;
  final DateTime createdAt;

  /// 是否已被飞手接单
  final bool accepted;
  final DateTime? acceptedAt;

  /// 预估费用 = 面积 × 单价
  double get amount => area * unitPrice;

  BookingOrder copyWith({
    bool? accepted,
    DateTime? acceptedAt,
    bool clearAcceptedAt = false,
  }) {
    return BookingOrder(
      id: id,
      crop: crop,
      area: area,
      unitPrice: unitPrice,
      address: address,
      time: time,
      pilotName: pilotName,
      contactName: contactName,
      phone: phone,
      note: note,
      createdAt: createdAt,
      accepted: accepted ?? this.accepted,
      acceptedAt: clearAcceptedAt ? null : (acceptedAt ?? this.acceptedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'crop': crop,
        'area': area,
        'unitPrice': unitPrice,
        'address': address,
        'time': time,
        'pilotName': pilotName,
        'contactName': contactName,
        'phone': phone,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'accepted': accepted,
        'acceptedAt': acceptedAt?.toIso8601String(),
      };

  factory BookingOrder.fromJson(Map<String, dynamic> json) {
    final acceptedAt = json['acceptedAt'];
    return BookingOrder(
      id: '${json['id'] ?? ''}',
      crop: '${json['crop'] ?? ''}',
      area: _toDouble(json['area']),
      unitPrice: _toDouble(json['unitPrice']),
      address: '${json['address'] ?? ''}',
      time: '${json['time'] ?? ''}',
      pilotName: '${json['pilotName'] ?? ''}',
      contactName: '${json['contactName'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      note: '${json['note'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ??
          DateTime.now(),
      accepted: json['accepted'] == true,
      acceptedAt:
          acceptedAt is String ? DateTime.tryParse(acceptedAt) : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

/// 预约订单共享存储：农户提交、飞手接单都读写同一份数据
class BookingOrderStore extends ChangeNotifier {
  BookingOrderStore._();

  static final BookingOrderStore instance = BookingOrderStore._();

  static const String storageKey = 'booking_orders';

  /// 全部订单，最新的在前
  List<BookingOrder> get orders {
    final raw = LocalDatabase().get(storageKey);
    if (raw == null || raw.isEmpty) return <BookingOrder>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(BookingOrder.fromJson)
          .toList();
    } catch (_) {
      return <BookingOrder>[];
    }
  }

  List<BookingOrder> get pending =>
      orders.where((order) => !order.accepted).toList();

  List<BookingOrder> get acceptedOrders =>
      orders.where((order) => order.accepted).toList();

  void add(BookingOrder order) {
    final list = orders..insert(0, order);
    _save(list);
  }

  void accept(String id) {
    final list = orders;
    final index = list.indexWhere((order) => order.id == id);
    if (index < 0) return;
    list[index] = list[index]
        .copyWith(accepted: true, acceptedAt: DateTime.now());
    _save(list);
  }

  void cancel(String id) {
    final list = orders;
    final index = list.indexWhere((order) => order.id == id);
    if (index < 0) return;
    list[index] =
        list[index].copyWith(accepted: false, clearAcceptedAt: true);
    _save(list);
  }

  void _save(List<BookingOrder> list) {
    LocalDatabase().set(
      storageKey,
      jsonEncode(list.map((order) => order.toJson()).toList()),
    );
    notifyListeners();
  }
}
