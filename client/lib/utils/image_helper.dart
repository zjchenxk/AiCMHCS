import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:client/utils/log_helper.dart';
import 'package:image_picker/image_picker.dart';

/// 图片选择与校验工具：分辨率校验 + 转 base64
class ImageHelper {
  /// 从相册选择图片，校验分辨率宽、高分别不超过 [maxWidth]/[maxHeight]，
  /// 校验通过则返回 base64 字符串，失败返回 null 并通过 [onError] 提示。
  static Future<String?> pickAndConvert({
    required int maxWidth,
    required int maxHeight,
    required void Function(String msg) onError,
  }) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return null; // 用户取消

      final Uint8List bytes = await picked.readAsBytes();

      // 解码图片获取实际分辨率。须用 instantiateImageCodec 解码首帧取
      // 宽高：ImageDescriptor 在 Web 平台不支持（width/height 抛
      // Unsupported operation），codec 方式三端（Web/桌面/移动）通用
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final int w = frame.image.width;
      final int h = frame.image.height;
      frame.image.dispose();
      codec.dispose();

      if (w > maxWidth || h > maxHeight) {
        onError('图片分辨率 ${w}x$h 超出限制，要求不超过 ${maxWidth}x$maxHeight');
        return null;
      }
      return base64Encode(bytes);
    } catch (e, st) {
      LogHelper.error('client:ImageHelper.pickAndConvert', e, st);
      onError('图片处理失败：$e');
      return null;
    }
  }
}
