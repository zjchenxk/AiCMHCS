import 'dart:typed_data';

/// 非 Web 平台桩实现：本地图片归一化/裁剪能力不可用（系统当前仅交付
/// Chrome Web 端）。
class WebImageCropper {
  /// 把任意本地照片字节归一化为等比缩放铺满居中裁边的
  /// coverWidth×coverHeight JPEG（并缓存结果供 [cropLast] 复用）。
  ///throws: UnsupportedError（非 Web 平台）
  Future<Uint8List> coverFit(Uint8List bytes, int coverWidth, int coverHeight) async {
    throw UnsupportedError('本地图片裁剪仅支持 Web 平台');
  }

  /// 从最近一次 [coverFit] 的结果上裁剪：源区域 (sx,sy) 起 720×900 生成
  /// 照片，同区域中心方阵缩放生成 320×320 头像，同区域等比缩放生成
  /// 180×225 缩略图。
  ///returns: (photoBytes, avatarBytes, thumbBytes)
  ///throws: UnsupportedError（非 Web 平台）
  Future<(Uint8List, Uint8List, Uint8List)> cropLast(int sx, int sy) async {
    throw UnsupportedError('本地图片裁剪仅支持 Web 平台');
  }
}
