import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 护花使者自研轻量加密图像容器（.ys 后缀）
///
/// 格式（v1）：
///   [0-1]  魔数 'Y''S'
///   [2]    版本号 0x01
///   [3]    保留标志 0x00
///   [4-7]  原始JPEG负载长度（小端 uint32）
///   [8-11] 长度校验码 = 负载长度 * 0x9E3779B9 截断32位（小端）
///   [12..] 负载：JPEG字节流经滚动密钥异或混淆
///
/// 滚动密钥由魔数、版本、负载长度派生，逐字节递进更新。
/// 只有本 App 知道该格式，外部程序即使拿到文件也无法直接浏览。
/// 采集的原始图片不入系统相册，仅存应用私有目录。
class YsImageStore {
  static final YsImageStore _instance = YsImageStore._();
  factory YsImageStore() => _instance;
  YsImageStore._();

  static const int _magic0 = 0x59; // 'Y'
  static const int _magic1 = 0x53; // 'S'
  static const int _version = 0x01;
  static const int _headerLen = 12;
  static const int _maxDimension = 1280;
  static const int _jpegQuality = 72;

  String? _baseDir;

  static const MethodChannel _galleryChannel = MethodChannel('com.huhuashizhe/gallery');

  Future<String> _getBaseDir() async {
    if (_baseDir != null) return _baseDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/huhuashizhe_data/growth_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    _baseDir = dir.path;
    return dir.path;
  }

  /// 压缩 + 加密，写入 [recordId] 目录，返回完整文件路径（xxx.ys）
  ///
  /// [jpegBytes] 为摄像头拍摄的原始JPEG数据。
  /// 先做轻量压缩（等比缩放到最长边1280px内 + JPEG重编码），
  /// 再经过滚动密钥混淆后落盘。
  Future<String> saveCapturedImage(String recordId, Uint8List jpegBytes) async {
    final compressed = await _compressJpeg(jpegBytes);
    final encrypted = encryptBytes(compressed);
    final baseDir = await _getBaseDir();
    final dir = Directory('$baseDir/$recordId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final fileName =
        'ys_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}.ys';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(encrypted, flush: true);
    return file.path;
  }

  /// 解密并返回原始JPEG字节（仅 App 内部使用）
  Uint8List decryptBytes(Uint8List data) {
    if (data.length < _headerLen) {
      throw const FormatException('YS文件头不完整');
    }
    if (data[0] != _magic0 || data[1] != _magic1 || data[2] != _version) {
      throw const FormatException('不是有效的YS图像文件');
    }
    final bd = ByteData.sublistView(data);
    final payloadLen = bd.getUint32(4, Endian.little);
    final check = bd.getUint32(8, Endian.little);
    final expectedCheck =
        (payloadLen * 0x9E3779B9) & 0xFFFFFFFF;
    if (check != expectedCheck) {
      throw const FormatException('YS文件校验失败');
    }
    if (data.length < _headerLen + payloadLen) {
      throw const FormatException('YS文件负载不完整');
    }
    return _unxor(data, _headerLen, payloadLen);
  }

  /// 读取 .ys 文件并解密为JPEG字节
  Future<Uint8List> readImageBytes(String ysPath) async {
    final bytes = await File(ysPath).readAsBytes();
    return decryptBytes(Uint8List.fromList(bytes));
  }

  /// 将 .ys 图片导出保存到系统相册（唯一的对外出口）
  ///
  /// 解密到临时文件 → 通过原生 MediaStore 通道保存 → 删除临时文件。
  Future<bool> exportToGallery(String ysPath) async {
    final jpeg = await readImageBytes(ysPath);
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tempFile = File('${tempDir.path}/ys_export_$ts.jpg');
    await tempFile.writeAsBytes(jpeg, flush: true);
    try {
      final displayName = 'HHS_$ts.jpg';
      await _galleryChannel.invokeMethod('saveImageToGallery', {
        'path': tempFile.path,
        'displayName': displayName,
      });
      return true;
    } on PlatformException {
      return false;
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  /// 删除记录对应的全部图片文件
  Future<void> deleteRecordImages(String recordId, List<String> ysPaths) async {
    for (final p in ysPaths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    final baseDir = await _getBaseDir();
    final dir = Directory('$baseDir/$recordId');
    if (await dir.exists()) {
      final remaining = await dir.list().toList();
      if (remaining.isEmpty) await dir.delete();
    }
  }

  /// 轻量压缩：解码 → 等比缩放（最长边≤1280）→ JPEG重编码
  Future<Uint8List> _compressJpeg(Uint8List jpegBytes) async {
    return Uint8List.fromList(
      await Future(() {
        final decoded = img.decodeJpg(jpegBytes);
        if (decoded == null) {
          throw const FormatException('无法解码采集图像');
        }
        var image = decoded;
        final maxSide = image.width > image.height ? image.width : image.height;
        if (maxSide > _maxDimension) {
          final ratio = _maxDimension / maxSide;
          final w = (image.width * ratio).round();
          final h = (image.height * ratio).round();
          image = img.copyResize(image, width: w, height: h,
              interpolation: img.Interpolation.average);
        }
        return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
      }),
    );
  }

  /// 加密：加头部 + 滚动密钥异或
  Uint8List encryptBytes(Uint8List payload) {
    final out = Uint8List(_headerLen + payload.length);
    final bd = ByteData.view(out.buffer);
    out[0] = _magic0;
    out[1] = _magic1;
    out[2] = _version;
    out[3] = 0x00;
    bd.setUint32(4, payload.length, Endian.little);
    bd.setUint32(8, (payload.length * 0x9E3779B9) & 0xFFFFFFFF, Endian.little);

    var key = _deriveSeed(payload.length);
    for (var i = 0; i < payload.length; i++) {
      key = (key * 1664525 + 1013904223) & 0xFFFFFFFF;
      out[_headerLen + i] = payload[i] ^ ((key >> 24) & 0xFF);
    }
    return out;
  }

  Uint8List _unxor(Uint8List data, int offset, int payloadLen) {
    final out = Uint8List(payloadLen);
    var key = _deriveSeed(payloadLen);
    for (var i = 0; i < payloadLen; i++) {
      key = (key * 1664525 + 1013904223) & 0xFFFFFFFF;
      out[i] = data[offset + i] ^ ((key >> 24) & 0xFF);
    }
    return out;
  }

  int _deriveSeed(int payloadLen) {
    var seed = 0x48534B59; // 'HSKY'
    seed = (seed ^ (payloadLen & 0xFFFF)) & 0xFFFFFFFF;
    seed = (seed * 2654435761) & 0xFFFFFFFF;
    seed ^= (payloadLen >>> 16);
    return seed & 0x7FFFFFFF;
  }

  static int _seq = 0;

  String _randomSuffix() {
    _seq = (_seq + 1) % 10000;
    return _seq.toString().padLeft(4, '0');
  }
}
