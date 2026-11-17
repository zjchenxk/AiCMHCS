import 'dart:convert';
import 'dart:typed_data';

import 'package:client/utils/captured_photo.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/web_camera.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 拍照对话框（独立组件，儿童建档/儿童照片管理等场景复用）。
///
/// 流程：枚举本机摄像头（记住上次选择，设备消失时自动回退首个）→
/// 打开预览（按设备支持能力请求 1200×1080）→【拍照】截取静帧 → 拖动
/// 720×900 裁剪框（双击完成裁剪）→ 预览 720×900 照片与缩放生成的
/// 320×320 头像 →【确定】返回 CapturedPhoto 随儿童档案保存一并入库；
/// 【重拍】回到预览，【取消】放弃。典型姿势为儿童站在固定摄像头前，
/// 拍照后再在电脑上移动裁剪框取景。
class CameraCaptureDialog extends StatefulWidget {
  const CameraCaptureDialog({super.key});

  /// 打开拍照对话框，返回拍照结果；取消/失败返回 null。
  static Future<CapturedPhoto?> show(BuildContext context) {
    return showDialog<CapturedPhoto>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const CameraCaptureDialog(),
    );
  }

  @override
  State<CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

enum _Stage { loading, live, crop, result }

class _CameraCaptureDialogState extends State<CameraCaptureDialog> {
  final WebCamera _camera = WebCamera();

  /// 摄像头记忆偏好 key（SharedPreferences 即浏览器 localStorage，
  /// 天然按机器隔离）。
  static const String _rememberedDeviceKey = 'camera_device_id';

  // 显示几何：预览/静帧按 1200×1080 × 0.4 显示；裁剪框 720×900 同比例
  static const double _displayWidth = 480;
  static const double _displayHeight = 432;
  static const double _scale = 0.4;
  static const double _cropDisplayWidth = 288;
  static const double _cropDisplayHeight = 360;

  _Stage _stage = _Stage.loading;
  List<WebCameraDevice> _cameras = const [];
  String? _selectedDeviceId;
  String? _viewId;
  String? _error;

  Uint8List? _frameBytes;
  Uint8List? _photoBytes;
  Uint8List? _avatarBytes;
  Offset _cropOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _initCameras();
  }

  @override
  void dispose() {
    // fire-and-forget：对话框已关闭，流停止失败无补救意义
    _camera.close();
    super.dispose();
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 枚举摄像头并恢复「记住的摄像头」（不存在则回退第一个）。
  Future<void> _initCameras() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      _cameras = await _camera.listCameras();
      if (_cameras.isEmpty) {
        throw Exception('未检测到可用摄像头，请确认设备已连接并在浏览器中授权');
      }
      final prefs = await SharedPreferences.getInstance();
      final remembered = prefs.getString(_rememberedDeviceKey);
      final matched = _cameras.where((c) => c.deviceId == remembered).toList();
      _selectedDeviceId = matched.isNotEmpty ? matched.first.deviceId : _cameras.first.deviceId;
      if (_selectedDeviceId != remembered) {
        await prefs.setString(_rememberedDeviceKey, _selectedDeviceId!);
      }
      await _openSelected();
    } catch (e, st) {
      LogHelper.error('client:CameraCaptureDialog._initCameras', e, st);
      setState(() {
        _stage = _Stage.loading;
        _error = _messageOf(e);
      });
    }
  }

  /// 打开当前选中的摄像头并进入预览。
  Future<void> _openSelected() async {
    setState(() {
      _stage = _Stage.live;
      _error = null;
    });
    try {
      _viewId = await _camera.open(_selectedDeviceId);
      setState(() {});
    } catch (e, st) {
      LogHelper.error('client:CameraCaptureDialog._openSelected', e, st);
      setState(() {
        _stage = _Stage.loading;
        _error = '打开摄像头失败：${_messageOf(e)}';
      });
    }
  }

  /// 切换摄像头（记住新选择并重开预览）。
  Future<void> _switchCamera(String deviceId) async {
    if (deviceId == _selectedDeviceId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedDeviceKey, deviceId);
    setState(() => _selectedDeviceId = deviceId);
    await _openSelected();
  }

  /// 拍照：截取预览帧为 1200×1080 静帧，进入裁剪阶段（裁剪框居中）。
  void _capture() {
    try {
      final frame = _camera.captureFrame();
      setState(() {
        _frameBytes = frame;
        _cropOffset = Offset(
          (_displayWidth - _cropDisplayWidth) / 2,
          (_displayHeight - _cropDisplayHeight) / 2,
        );
        _stage = _Stage.crop;
      });
    } catch (e, st) {
      LogHelper.error('client:CameraCaptureDialog._capture', e, st);
      _showError('拍照失败：${_messageOf(e)}');
    }
  }

  /// 双击裁剪框：按裁剪框位置截出 720×900 照片并缩放生成 320×320 头像，
  /// 进入结果阶段。
  Future<void> _applyCrop() async {
    final frame = _frameBytes;
    if (frame == null) return;
    setState(() => _stage = _Stage.result);
    try {
      final sx = (_cropOffset.dx / _scale).round().clamp(0, 1200 - 720);
      final sy = (_cropOffset.dy / _scale).round().clamp(0, 1080 - 900);
      final (photo, avatar) = await _camera.cropLastFrame(sx, sy);
      setState(() {
        _photoBytes = photo;
        _avatarBytes = avatar;
      });
    } catch (e, st) {
      LogHelper.error('client:CameraCaptureDialog._applyCrop', e, st);
      // 裁剪失败回到预览重拍
      setState(() => _stage = _Stage.live);
      _showError('裁剪失败：${_messageOf(e)}');
    }
  }

  /// 确定返回拍照结果。
  void _confirm() {
    final photo = _photoBytes;
    final avatar = _avatarBytes;
    if (photo == null || avatar == null) return;
    Navigator.of(context).pop(
      CapturedPhoto(
        photoBase64: base64Encode(photo),
        avatarBase64: base64Encode(avatar),
      ),
    );
  }

  void _cancel() {
    _camera.close();
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
      // 会把面板撑满整窗，右侧留大片空白（与其他对话框的 maxWidth 约束
      // 同款模式）
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
                    Icon(Icons.photo_camera_outlined, color: theme.colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      '儿童拍照',
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
      case _Stage.loading:
        return _previewBox(
          theme,
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_error ?? '正在初始化摄像头...', style: theme.textTheme.bodyMedium),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _initCameras, child: const Text('重试')),
                ],
              ],
            ),
          ),
        );
      case _Stage.live:
        return _buildLive(theme);
      case _Stage.crop:
        return _buildCrop(theme);
      case _Stage.result:
        return _buildResult(theme);
    }
  }

  /// 预览阶段：摄像头选择 + 视频画面（HTML 元素只占画面区域，按钮均在
  /// 区域外，避免 DOM 元素遮挡 Flutter 控件）。
  Widget _buildLive(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDeviceId,
                isExpanded: true,
                items: _cameras
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.deviceId,
                        child: Text(c.label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                hint: Text('请选择摄像头', style: theme.textTheme.bodyMedium),
                decoration: childGlassDecoration(theme, '摄像头'),
                style: theme.textTheme.bodyMedium,
                onChanged: (id) {
                  if (id != null) _switchCamera(id);
                },
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '无目标设备？请检查连接并重新授权',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 视频预览（HTML 平台视图； Flutter 控件只放在画面区域外，避免
        // DOM 元素在合成层上遮挡 Flutter 绘制的内容）
        _previewBox(
          theme,
          _viewId == null ? const Center(child: CircularProgressIndicator()) : HtmlElementView(viewType: _viewId!),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _cancel, child: const Text('取消')),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('拍 照'),
            ),
          ],
        ),
      ],
    );
  }

  /// 裁剪阶段：1200×1080 静帧 + 可拖动 720×900 裁剪框（双击裁剪）。
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
                  onDoubleTap: _applyCrop,
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '拖动绿色裁剪框对准儿童（裁剪范围 720×900），双击裁剪框完成取景',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: _cancel, child: const Text('取消')),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stage = _Stage.live),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重 拍'),
            ),
          ],
        ),
      ],
    );
  }

  /// 结果阶段：左 720×900 照片、右 320×320 头像，确定后随档案保存入库。
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
              onPressed: () => setState(() => _stage = _Stage.live),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重 拍'),
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
