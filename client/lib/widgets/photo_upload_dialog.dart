import 'dart:convert';
import 'dart:typed_data';

import 'package:client/utils/captured_photo.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/web_image.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

/// 照片上传对话框（独立组件，儿童照片管理等场景复用）。
///
/// 流程：【选择照片】从本地相册选图（接受任意尺寸）→ 归一化为等比
/// 缩放铺满居中裁边的 1200×1080 图像 → 拖动 720×900 裁剪框（双击完成
/// 裁剪）→ 预览 720×900 照片与缩放生成的 320×320 头像（缩略图 180×225
/// 随返回值携带、不展示）→【确定】返回 CapturedPhoto 由调用方入库；
/// 【重新选择】回到选图，【重新裁剪】回到裁剪框，【取消】放弃。
class PhotoUploadDialog extends StatefulWidget {
  const PhotoUploadDialog({super.key});

  /// 打开照片上传对话框，返回裁剪结果；取消/失败返回 null。
  static Future<CapturedPhoto?> show(BuildContext context) {
    return showDialog<CapturedPhoto>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const PhotoUploadDialog(),
    );
  }

  @override
  State<PhotoUploadDialog> createState() => _PhotoUploadDialogState();
}

enum _Stage { pick, crop, result }

class _PhotoUploadDialogState extends State<PhotoUploadDialog> {
  final WebImageCropper _cropper = WebImageCropper();

  /// 原始文件软上限（防浏览器解码超大图 OOM；归一化后单字段远小于
  /// 服务端 1MB 限长）。
  static const int _sourceBytesMaxLength = 20 * 1024 * 1024;

  // 显示几何：与拍照对话框同口径——预览按 1200×1080 × 0.4 显示；裁剪
  // 框 720×900 同比例。
  static const double _displayWidth = 480;
  static const double _displayHeight = 432;
  static const double _scale = 0.4;
  static const double _cropDisplayWidth = 288;
  static const double _cropDisplayHeight = 360;

  _Stage _stage = _Stage.pick;
  bool _busy = false;
  String? _error;

  Uint8List? _frameBytes;
  Uint8List? _photoBytes;
  Uint8List? _avatarBytes;
  Uint8List? _thumbBytes;
  Offset _cropOffset = Offset.zero;

  /// 裁剪进行中（结果阶段须等字节就绪再进入——先切后填会整屏红闪
  /// 空引用错误；同时防双击连触重入）。
  bool _cropping = false;

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 选择本地照片并归一化为 1200×1080（等比缩放铺满居中裁边），进入
  /// 裁剪阶段（裁剪框居中）。
  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) {
        // 用户取消选择，维持选图界面
        setState(() => _busy = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.lengthInBytes > _sourceBytesMaxLength) {
        throw Exception('照片文件过大（超过 20MB），请压缩后再上传');
      }
      final frame = await _cropper.coverFit(bytes, 1200, 1080);
      setState(() {
        _frameBytes = frame;
        _cropOffset = Offset(
          (_displayWidth - _cropDisplayWidth) / 2,
          (_displayHeight - _cropDisplayHeight) / 2,
        );
        _stage = _Stage.crop;
        _busy = false;
      });
    } catch (e, st) {
      LogHelper.error('client:PhotoUploadDialog._pick', e, st);
      setState(() {
        _busy = false;
        _error = _messageOf(e);
      });
    }
  }

  /// 双击裁剪框：按裁剪框位置截出 720×900 照片并缩放生成 320×320 头像
  /// 与 180×225 缩略图，裁剪完成后才切到结果阶段（结果阶段直接解引用
  /// 照片/头像字节，先切后填会在首次裁剪时整屏红闪空引用错误）。
  Future<void> _applyCrop() async {
    final frame = _frameBytes;
    if (frame == null || _cropping) return;
    setState(() => _cropping = true);
    try {
      final sx = (_cropOffset.dx / _scale).round().clamp(0, 1200 - 720);
      final sy = (_cropOffset.dy / _scale).round().clamp(0, 1080 - 900);
      final (photo, avatar, thumb) = await _cropper.cropLast(sx, sy);
      if (!mounted) return;
      setState(() {
        _photoBytes = photo;
        _avatarBytes = avatar;
        _thumbBytes = thumb;
        _cropping = false;
        _stage = _Stage.result;
      });
    } catch (e, st) {
      LogHelper.error('client:PhotoUploadDialog._applyCrop', e, st);
      // 裁剪失败留在裁剪阶段，可直接重试
      if (mounted) {
        setState(() => _cropping = false);
      }
      _showError('裁剪失败：${_messageOf(e)}');
    }
  }

  /// 确定返回上传裁剪结果。
  void _confirm() {
    final photo = _photoBytes;
    final avatar = _avatarBytes;
    final thumb = _thumbBytes;
    if (photo == null || avatar == null || thumb == null) return;
    Navigator.of(context).pop(
      CapturedPhoto(
        photoBase64: base64Encode(photo),
        avatarBase64: base64Encode(avatar),
        thumbBase64: base64Encode(thumb),
      ),
    );
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      // 面板宽度须显式收敛到内容宽（预览 480 + 左右内距 48）：Dialog 给
      // 子树的约束上限是整窗宽，GlassPanel 内的 Row 默认 mainAxisSize.max
      // 会把面板撑满整窗（与拍照对话框同款模式）
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 528),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.upload_outlined, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      '照片上传',
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildContent(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_stage) {
      case _Stage.pick:
        return _buildPick(theme);
      case _Stage.crop:
        return _buildCrop(theme);
      case _Stage.result:
        return _buildResult(theme);
    }
  }

  /// 选图阶段：说明文案 + 选择照片按钮（归一化处理中显示进度）。
  Widget _buildPick(ThemeData theme) {
    return SizedBox(
      width: _displayWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _displayWidth,
            height: _displayHeight,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              color: theme.colorScheme.surface,
            ),
            clipBehavior: Clip.antiAlias,
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _error ?? '从本地相册选择一张照片\n（任意尺寸，上传后自动归一化为 1200×1080）',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            '照片归一化为等比缩放铺满、居中裁边的 1200×1080 图像，超出显示区的边缘将被裁掉',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _busy ? null : _cancel, child: const Text('取消')),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择照片'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 裁剪阶段：1200×1080 归一化图 + 可拖动 720×900 裁剪框（双击裁剪）。
  Widget _buildCrop(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _previewBox(
          theme,
          Stack(
            children: [
              Positioned.fill(
                child: Image.memory(
                  _frameBytes!,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              Positioned(
                left: _cropOffset.dx,
                top: _cropOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _cropOffset = Offset(
                        (_cropOffset.dx + details.delta.dx).clamp(0, _displayWidth - _cropDisplayWidth),
                        (_cropOffset.dy + details.delta.dy).clamp(0, _displayHeight - _cropDisplayHeight),
                      );
                    });
                  },
                  onDoubleTap: _cropping ? null : _applyCrop,
                  child: Container(
                    width: _cropDisplayWidth,
                    height: _cropDisplayHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        width: double.infinity,
                        child: Text(
                          '拖动取景 · 双击裁剪',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 裁剪进行中：盖住画面防重复触发，字节就绪后才切结果阶段
              if (_cropping)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.6),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text('裁剪中...', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '拖动绿色裁剪框取景（裁剪范围 720×900），双击裁剪框完成取景',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _cancel, child: const Text('取消')),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _cropping ? null : () => setState(() => _stage = _Stage.pick),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新选择'),
            ),
          ],
        ),
      ],
    );
  }

  /// 结果阶段：左 720×900 照片、右 320×320 头像，确定后由调用方入库。
  Widget _buildResult(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Image.memory(_photoBytes!, width: 240, height: 300, fit: BoxFit.fill, gaplessPlayback: true),
                const SizedBox(height: 6),
                Text('照片（720×900）', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(width: 24),
            Column(
              children: [
                Image.memory(_avatarBytes!, width: 160, height: 160, fit: BoxFit.fill, gaplessPlayback: true),
                const SizedBox(height: 6),
                Text('头像（320×320）', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _cancel, child: const Text('取消')),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stage = _Stage.pick),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新选择'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stage = _Stage.crop),
              icon: const Icon(Icons.crop_outlined, size: 18),
              label: const Text('重新裁剪'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('确 定'),
            ),
          ],
        ),
      ],
    );
  }

  /// 画面容器（统一 480×432 显示区，对应源 1200×1080）。
  Widget _previewBox(ThemeData theme, Widget child) {
    return Container(
      width: _displayWidth,
      height: _displayHeight,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
