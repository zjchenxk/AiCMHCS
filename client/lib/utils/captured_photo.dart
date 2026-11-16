import 'dart:convert';
import 'dart:typed_data';

/// 拍照确定后的产出：720×900 照片与 320×320 头像（JPEG base64），
/// 由拍照对话框返回、随儿童档案保存一并入库。
class CapturedPhoto {
  const CapturedPhoto({required this.photoBase64, required this.avatarBase64});

  /// 照片（竖版 720×900，JPEG base64，无 data: 前缀）。
  final String photoBase64;

  /// 头像（320×320，JPEG base64）。
  final String avatarBase64;

  /// 照片字节（界面 Image.memory 显示用）。
  Uint8List get photoBytes => base64Decode(photoBase64);

  /// 头像字节（界面 Image.memory 显示用）。
  Uint8List get avatarBytes => base64Decode(avatarBase64);
}
