import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
// 本文件为 Web 平台实现（经条件导入仅在选择 dart:html 的平台编译）：
// dart:html 已被官方标记废弃（推荐 package:web），此处沿用以零依赖落地
// 本地图片的 Canvas 离屏绘制（Blob URL 加载与区域裁剪），升级路径可
// 替换为 package:web（与 web_camera_html.dart 同款取舍）。
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web 平台本地照片归一化与裁剪实现：Blob URL 加载 ImageElement，经
/// CanvasElement 离屏绘制完成「等比缩放铺满居中裁边」归一化与区域
/// 裁剪缩放（几何与 WebCamera 截帧/裁剪同口径）。
class WebImageCropper {
  String _dataUrl = '';

  /// 把任意本地照片字节归一化为等比缩放铺满居中裁边的
  /// coverWidth×coverHeight JPEG：scale = max(coverW/w, coverH/h)，居中
  /// 对齐、超界部分由画布裁掉（比例不变形）。缓存结果 dataURL 供
  /// [cropLast] 复用。
  ///throws: Exception（图像解码失败）
  Future<Uint8List> coverFit(Uint8List bytes, int coverWidth, int coverHeight) async {
    final source = await _loadImageFromBytes(bytes);
    final scale = math.max(coverWidth / source.naturalWidth, coverHeight / source.naturalHeight);
    final drawWidth = source.naturalWidth * scale;
    final drawHeight = source.naturalHeight * scale;
    final canvas = html.CanvasElement(width: coverWidth, height: coverHeight);
    final ctx = canvas.getContext('2d')! as html.CanvasRenderingContext2D;
    // 居中铺满：负偏移部分被画布裁掉，即「居中裁边」
    ctx.drawImageScaled(source, (coverWidth - drawWidth) / 2, (coverHeight - drawHeight) / 2, drawWidth, drawHeight);
    _dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    return base64Decode(_dataUrl.split(',').last);
  }

  /// 从最近一次 [coverFit] 的结果上裁剪：源区域 (sx,sy) 起 720×900 生成
  /// 照片；同区域中心方阵（720×720）缩放为 320×320 生成头像；同区域
  /// 等比缩放为 180×225 生成缩略图。
  ///returns: (photoBytes, avatarBytes, thumbBytes)
  ///throws: StateError（尚未归一化）
  Future<(Uint8List, Uint8List, Uint8List)> cropLast(int sx, int sy) async {
    if (_dataUrl.isEmpty) {
      throw StateError('尚未归一化本地照片');
    }
    final source = await _loadImage(_dataUrl);
    final photo = _cropToBytes(source, sx, sy, 720, 900, 720, 900);
    final avatar = _cropToBytes(source, sx, sy + 90, 720, 720, 320, 320);
    final thumb = _cropToBytes(source, sx, sy, 720, 900, 180, 225);
    return (photo, avatar, thumb);
  }

  Future<html.ImageElement> _loadImage(String src) async {
    final img = html.ImageElement();
    final completer = Completer<void>();
    img.onLoad.listen((_) => completer.complete());
    img.onError.listen((_) => completer.completeError(Exception('图像解码失败')));
    img.src = src;
    await completer.future;
    return img;
  }

  /// 经 Blob URL 加载本地照片字节（不假定编码格式，浏览器自行嗅探；
  /// 加载完成后立即释放 URL）。
  Future<html.ImageElement> _loadImageFromBytes(Uint8List bytes) async {
    final url = html.Url.createObjectUrl(html.Blob([bytes]));
    try {
      return await _loadImage(url);
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }

  Uint8List _cropToBytes(html.ImageElement source, int sx, int sy, int sw, int sh, int dw, int dh) {
    final canvas = html.CanvasElement(width: dw, height: dh);
    final ctx = canvas.getContext('2d')! as html.CanvasRenderingContext2D;
    ctx.drawImageScaledFromSource(source, sx, sy, sw, sh, 0, 0, dw, dh);
    final url = canvas.toDataUrl('image/jpeg', 0.92);
    return base64Decode(url.split(',').last);
  }
}
