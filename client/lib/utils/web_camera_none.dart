import 'dart:typed_data';

import 'package:client/utils/web_camera.dart';

/// 非 Web 平台桩实现：拍照能力不可用（系统当前仅交付 Chrome Web 端）。
class WebCamera {
  /// 枚举摄像头设备。
  ///throws: UnsupportedError（非 Web 平台）
  Future<List<WebCameraDevice>> listCameras() async {
    throw UnsupportedError('摄像头仅支持 Web 平台');
  }

  /// 打开指定设备并注册预览平台视图，返回 HtmlElementView 的 viewType。
  ///param deviceId: 设备 ID（null/空为系统默认摄像头）
  Future<String> open(String? deviceId) async {
    throw UnsupportedError('摄像头仅支持 Web 平台');
  }

  /// 截取当前预览帧（缩放至 1200×1080 的 JPEG 字节）。
  Uint8List captureFrame() {
    throw UnsupportedError('摄像头仅支持 Web 平台');
  }

  /// 从最近截取的帧上裁剪：源区域 (sx,sy) 起 720×900 生成照片，同区域
  /// 中心方阵缩放生成 320×320 头像，同区域等比缩放生成 180×225 缩略图。
  ///returns: (photoBytes, avatarBytes, thumbBytes)
  Future<(Uint8List, Uint8List, Uint8List)> cropLastFrame(int sx, int sy) async {
    throw UnsupportedError('摄像头仅支持 Web 平台');
  }

  /// 关闭摄像头并释放预览流。
  Future<void> close() async {}
}
