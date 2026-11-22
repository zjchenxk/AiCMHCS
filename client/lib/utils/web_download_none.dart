import 'dart:typed_data';

/// 非 Web 平台桩实现：字节流另存为本地文件不可用（系统当前仅交付
/// Chrome Web 端）。
///throws: UnsupportedError（非 Web 平台）
Future<void> saveBytes(Uint8List bytes, String filename, {String mime = 'image/jpeg'}) async {
  throw UnsupportedError('文件另存仅支持 Web 平台');
}
