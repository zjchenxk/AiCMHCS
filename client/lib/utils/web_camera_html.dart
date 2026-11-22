import 'dart:async';
import 'dart:convert';
// 本文件为 Web 平台实现（经条件导入仅在选择 dart:html 的平台编译）：
// dart:html 已被官方标记废弃（推荐 package:web），此处沿用以零依赖落地
// 摄像头采集（getUserMedia 与 Canvas 2D），升级路径可替换为 package:web。
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
// 平台视图注册在 3.32 已迁至 dart:ui_web（仅 web 编译平台提供；VM 静态
// 分析不可见，经 ignore 豁免——本文件经 web_camera.dart 条件导入只在
// web 编译）。
// ignore: uri_does_not_exist
import 'dart:ui_web' as ui_web;

import 'package:client/utils/web_camera.dart';

/// Web 平台摄像头实现：getUserMedia 打开视频流，经 platform view 注册
/// 为 HtmlElementView 预览；拍照/裁剪走 CanvasElement 离屏绘制。
class WebCamera {
  html.VideoElement? _video;

  html.MediaStream? _stream;

  String _viewType = '';

  String _frameDataUrl = '';

  /// 申请摄像头权限（未授权时枚举设备拿不到名称），返回设备清单
  /// （仅 videoinput，无名称的按序号兜底命名）。
  ///
  /// getTracks/enumerateDevices 走 dynamic 调用：3.32 的 dart:html 在
  /// DDC 运行时对这两个列表返回值声明的元素类型与实际 `JSArray<dynamic>`
  /// 不符，直调会触发隐式转换崩溃（`List` is not a subtype of
  /// `List<MediaStreamTrack>`）。
  Future<List<WebCameraDevice>> listCameras() async {
    final mediaDevices = html.window.navigator.mediaDevices!;
    final probe = await (mediaDevices as dynamic).getUserMedia({
      'video': true,
      'audio': false,
    });
    for (final track in probe.getTracks()) {
      (track as dynamic).stop();
    }

    final devices = await (mediaDevices as dynamic).enumerateDevices();
    final cameras = <WebCameraDevice>[];
    for (final device in devices) {
      final d = device as dynamic;
      if (d.kind != 'videoinput') {
        continue;
      }
      final label = (d.label as String?) ?? '';
      cameras.add(
        WebCameraDevice(
          (d.deviceId as String?) ?? '',
          label.isEmpty ? '摄像头 ${cameras.length + 1}' : label,
        ),
      );
    }
    return cameras;
  }

  /// 打开指定设备并注册预览平台视图，返回 HtmlElementView 的 viewType。
  ///param deviceId: 设备 ID（null/空为系统默认摄像头；请求 1200×1080
  /// 理想分辨率，浏览器取最接近的支持值）。
  Future<String> open(String? deviceId) async {
    await close();
    final video = deviceId == null || deviceId.isEmpty
        ? {
            'width': {'ideal': 1200},
            'height': {'ideal': 1080},
          }
        : {
            'deviceId': {'exact': deviceId},
            'width': {'ideal': 1200},
            'height': {'ideal': 1080},
          };
    final stream = await html.window.navigator.mediaDevices!.getUserMedia({
      'video': video,
      'audio': false,
    });
    _stream = stream;
    final element = html.VideoElement()
      ..srcObject = stream
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      // 与拍照帧同口径拉伸（drawImageScaled 亦为整帧缩放），预览即所得
      ..style.objectFit = 'fill';
    _video = element;
    _viewType = 'child-camera-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => element);
    return _viewType;
  }

  /// 预览平台视图类型（经 HtmlElementView(viewType:) 嵌入页面）。
  String get viewType => _viewType;

  /// 截取当前预览帧，缩放绘制为 1200×1080 的 JPEG（base64 解码后的
  /// 字节），同时保留 dataURL 供裁剪复用。
  ///throws: StateError（视频流未就绪）
  Uint8List captureFrame() {
    final video = _video;
    if (video == null || video.readyState < 2) {
      throw StateError('摄像头预览尚未就绪');
    }
    final canvas = html.CanvasElement(width: 1200, height: 1080);
    final ctx = canvas.getContext('2d')! as html.CanvasRenderingContext2D;
    ctx.drawImageScaled(video, 0, 0, 1200, 1080);
    _frameDataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    return base64Decode(_frameDataUrl.split(',').last);
  }

  /// 从最近截取的帧上裁剪：源区域 (sx,sy) 起 720×900 生成照片；同区域
  /// 中心方阵（720×720）缩放为 320×320 生成头像；同区域等比缩放为
  /// 180×225 生成缩略图。
  ///returns: (photoBytes, avatarBytes, thumbBytes)
  Future<(Uint8List, Uint8List, Uint8List)> cropLastFrame(int sx, int sy) async {
    final source = await _loadImage(_frameDataUrl);
    final photo = _cropToBytes(source, sx, sy, 720, 900, 720, 900);
    final avatar = _cropToBytes(source, sx, sy + 90, 720, 720, 320, 320);
    final thumb = _cropToBytes(source, sx, sy, 720, 900, 180, 225);
    return (photo, avatar, thumb);
  }

  /// 关闭摄像头并释放预览流（getTracks 走 dynamic 调用，理由同
  /// [listCameras]）。
  Future<void> close() async {
    final stream = _stream;
    if (stream != null) {
      for (final track in (stream as dynamic).getTracks()) {
        (track as dynamic).stop();
      }
    }
    _stream = null;
    _video?.srcObject = null;
    _video = null;
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

  Uint8List _cropToBytes(html.ImageElement source, int sx, int sy, int sw, int sh, int dw, int dh) {
    final canvas = html.CanvasElement(width: dw, height: dh);
    final ctx = canvas.getContext('2d')! as html.CanvasRenderingContext2D;
    ctx.drawImageScaledFromSource(source, sx, sy, sw, sh, 0, 0, dw, dh);
    final url = canvas.toDataUrl('image/jpeg', 0.92);
    return base64Decode(url.split(',').last);
  }
}
