import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

/// 图片选择与校验工具：分辨率校验 + 转 base64
class ImageUtil {
  /// 从相册选择图片，校验分辨率不超过 [maxSize]（宽或高均不超过），
  /// 校验通过则返回 base64 字符串，失败返回 null 并通过 [onError] 提示。
  static Future<String?> pickAndConvert({required int maxSize, required void Function(String msg) onError}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return null; // 用户取消

      final Uint8List bytes = await picked.readAsBytes();

      // 解码图片获取实际分辨率
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int w = descriptor.width;
      final int h = descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      if (w > maxSize || h > maxSize) {
        onError('图片分辨率 ${w}x$h 超出限制，要求不超过 ${maxSize}x$maxSize');
        return null;
      }
      return base64Encode(bytes);
    } catch (e) {
      onError('图片处理失败：$e');
      return null;
    }
  }
}
