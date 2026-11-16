/// Web 摄像头访问的条件导入门面：Web 平台（Chrome）经 getUserMedia
/// 枚举/打开摄像头、注册平台视图预览与帧截取；非 Web 平台为不可用桩。
///
/// 用法：`final camera = WebCamera();`——对话框等调用方不感知平台差异。
library;

export 'web_camera_none.dart' if (dart.library.html) 'web_camera_html.dart';

/// 摄像头设备描述。
class WebCameraDevice {
  const WebCameraDevice(this.deviceId, this.label);

  /// 设备 ID（浏览器会话内稳定，可持久化作为「记住的摄像头」）。
  final String deviceId;

  /// 设备名称（如「Integrated Camera」；未授权时浏览器不给 label）。
  final String label;
}
