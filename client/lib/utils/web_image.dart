/// 本地照片归一化与裁剪的条件导入门面：Web 平台经 Canvas 离屏绘制完成
/// 「等比缩放铺满居中裁边归一化 + 区域裁剪缩放」；非 Web 平台为不可用桩。
///
/// 用法：`final cropper = WebImageCropper();`——对话框等调用方不感知
/// 平台差异。与 [WebCamera]（web_camera.dart）的截帧/裁剪同几何口径：
/// 归一化 1200×1080 显示源、裁剪产出 720×900 照片 / 320×320 头像 /
/// 180×225 缩略图。
library;

export 'web_image_none.dart' if (dart.library.html) 'web_image_html.dart';
