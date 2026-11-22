import 'dart:convert';
import 'dart:typed_data';

import 'package:client/models/current_child.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/relative_time.dart';
import 'package:client/view_models/child/photo_management_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/widgets/camera_capture_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:client/widgets/photo_upload_dialog.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童照片管理页：展示当前儿童（主界面顶部搜索选定）在 CHILD_PHOTO 中
/// 的全部拍照记录（倒序最新在前，缩略图优先取照片等比缩略图、存量行为
/// 空时回退头像；卡片与预览均显示拍摄年龄「X岁X个月X天」），支持单击
/// 选中（再点同一张取消）、双击放大预览；【拍照】复用建档拍照对话框、
/// 【上传】走本地上传裁剪对话框，二者确定后立即入库并刷新；【下载】把
/// 选中照片的大图另存为本地文件；【删除】按 ID 删除选中照片。按钮按
/// 操作权限 0202000001-拍照/0202000002-上传/0202000003-下载/
/// 0202000004-删除灰化控制。
class PhotoManagementPage extends BasePage {
  const PhotoManagementPage({super.key, required super.loginUser, required super.child});

  @override
  State<PhotoManagementPage> createState() => _PhotoManagementPageState();
}

class _PhotoManagementPageState extends State<PhotoManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听。
  late final PhotoManagementViewModel _viewModel;

  late final MainViewModel _mainViewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<PhotoManagementViewModel>();
    _viewModel.addListener(_onViewModelChanged);
    // 主界面顶部搜索选定「当前儿童」变化时同步进本页（VM 内按 ID 幂等
    // 去重，儿童变化即清空选中并重载列表）
    _mainViewModel = context.read<MainViewModel>();
    _mainViewModel.addListener(_onMainChildChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    // 实例来自 Provider 全局注入，这里只移除监听，不要 viewModel.dispose()
    _mainViewModel.removeListener(_onMainChildChanged);
    _viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  Future<void> _init() async {
    final mainViewModel = _mainViewModel;
    await _viewModel.loadPermissions();
    final selected = mainViewModel.hasCurrentChild ? mainViewModel.child : null;
    await _viewModel.syncChild(selected);
  }

  /// 主界面「当前儿童」变化 → 同步（未选定则为 null，清空列表）。
  void _onMainChildChanged() {
    final selected = _mainViewModel.hasCurrentChild ? _mainViewModel.child : null;
    _viewModel.syncChild(selected);
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final theme = Theme.of(context);
    if (_viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_viewModel.errorMsg!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '关闭',
            textColor: theme.colorScheme.onPrimary,
            onPressed: _viewModel.clearError,
          ),
        ),
      );
      // 提示后立即清空，避免同一错误重复弹出
      _viewModel.clearError();
    }
  }

  /// 拍照：复用建档拍照对话框，确定后立即入库并刷新列表。
  Future<void> _startCapture() async {
    final result = await CameraCaptureDialog.show(context);
    if (result != null && mounted) {
      await _viewModel.saveCaptured(result);
    }
  }

  /// 上传：打开本地上传裁剪对话框，确定后立即入库并刷新列表。
  Future<void> _startUpload() async {
    final result = await PhotoUploadDialog.show(context);
    if (result != null && mounted) {
      await _viewModel.saveCaptured(result);
    }
  }

  /// 下载选中的照片（大图按需取用，Web 另存落地本地）。
  Future<void> _downloadSelected() async {
    await _viewModel.downloadSelected();
  }

  /// 删除选中的照片（带确认）。
  Future<void> _confirmDelete() async {
    final photo = _viewModel.selectedPhoto;
    if (photo == null) return;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.transparent,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400), // 收敛面板宽，防 Row 默认 max 撑满整窗留右侧空白
          child: GlassPanel(
            blur: 24,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('删除照片', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('将删除选中的这条拍照记录（含照片与头像），删除后不可恢复。确定删除吗？', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _viewModel.deleteSelected();
  }

  /// 双击放大预览：按需装载大图（InteractiveViewer 缩放）与元信息。
  Future<void> _previewPhoto(ChildPhoto photo) async {
    final id = photo.id;
    if (id == null) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => FutureBuilder<ChildPhoto?>(
        future: _viewModel.loadDetail(id),
        builder: (dialogContext, snapshot) {
          final bytes = snapshot.hasData ? _decodeBase64(snapshot.data!.photoBase64) : null;
          final detail = snapshot.data;
          return AlertDialog(
            backgroundColor: Colors.transparent,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
              child: GlassPanel(
                blur: 24,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(width: 240, height: 300, child: Center(child: CircularProgressIndicator()))
                      : bytes == null
                      ? SizedBox(
                          width: 240,
                          height: 300,
                          child: Center(
                            child: Text(
                              snapshot.hasError ? '照片装载失败：${_messageOf(snapshot.error!)}' : '照片内容缺失',
                              style: Theme.of(dialogContext).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('照片预览', style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Flexible(
                              child: InteractiveViewer(
                                maxScale: 8,
                                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '拍摄年龄：${detail == null ? '未知' : _photoAgeText(detail)}　创建人：${detail?.creatorName ?? '未知'}'
                              '${(detail?.deptName?.isNotEmpty ?? false) ? '　科室：${detail!.deptName}' : ''}',
                              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(color: Theme.of(dialogContext).colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('关闭')),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 裸 base64 → 字节（解码失败防红屏返回 null）。
  Uint8List? _decodeBase64(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementPage._decodeBase64', e, st);
      return null;
    }
  }

  /// 卡片/预览的拍摄年龄文案：岁/月/天复合（与儿童实足年龄同口径，见
  /// [photoTakenAgeLabel]）；拍摄时间解析失败或时钟偏差（拍摄时刻晚于
  /// 当前）时回退显示原始拍摄时间。
  String _photoAgeText(ChildPhoto photo) {
    final createTime = DateTime.tryParse(photo.createTime ?? '');
    if (createTime == null) return photo.createTime ?? '拍摄时间未知';
    final ageText = photoTakenAgeLabel(createTime);
    return ageText.isNotEmpty ? ageText : (photo.createTime ?? '拍摄时间未知');
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<PhotoManagementViewModel>();
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainer,
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          _buildToolbar(theme, viewModel),
          Expanded(child: _buildPhotoArea(theme, viewModel)),
        ],
      ),
    );
  }

  /// 顶部工具栏：当前儿童信息 + 拍照/上传/下载/删除 + 刷新。
  Widget _buildToolbar(ThemeData theme, PhotoManagementViewModel viewModel) {
    final child = viewModel.child;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_library_outlined, size: 20, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(
            '照片管理',
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: child == null
                ? Text('未选定儿童——请先在主界面顶部搜索选定', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8)))
                : Text(
                    _childSummary(child),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(width: 12),
          _toolbarButton(
            theme,
            icon: Icons.photo_camera_outlined,
            label: '拍照',
            tip: _captureTip(viewModel),
            enabled: viewModel.canCapture && viewModel.hasChild && !viewModel.busy,
            filled: true,
            onPressed: _startCapture,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            theme,
            icon: Icons.upload_outlined,
            label: '上传',
            tip: _uploadTip(viewModel),
            enabled: viewModel.canUpload && viewModel.hasChild && !viewModel.busy,
            filled: true,
            onPressed: _startUpload,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            theme,
            icon: Icons.download_outlined,
            label: '下载',
            tip: _downloadTip(viewModel),
            enabled: viewModel.canDownload && viewModel.selectedPhoto != null && !viewModel.busy,
            filled: false,
            onPressed: _downloadSelected,
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            theme,
            icon: Icons.delete_outlined,
            label: '删除',
            tip: _deleteTip(viewModel),
            enabled: viewModel.canDelete && viewModel.selectedPhoto != null && !viewModel.busy,
            filled: false,
            onPressed: _confirmDelete,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: viewModel.loading || viewModel.busy ? null : viewModel.loadPhotos,
          ),
        ],
      ),
    );
  }

  /// 当前儿童信息摘要（姓名/性别/实际年龄/就诊卡号，缺省项跳过）。
  String _childSummary(CurrentChild child) {
    final parts = <String>[
      child.name,
      if (child.gender.isNotEmpty) child.gender,
      if (child.actualAge.isNotEmpty) '实际年龄 ${child.actualAge}',
      if (child.visitCardNo.isNotEmpty) '就诊卡号 ${child.visitCardNo}',
    ];
    return parts.join(' · ');
  }

  String _captureTip(PhotoManagementViewModel viewModel) => !viewModel.canCapture
      ? '无拍照操作权限'
      : viewModel.hasChild
      ? '拍照'
      : '请先在主界面顶部搜索选定儿童';

  String _uploadTip(PhotoManagementViewModel viewModel) => !viewModel.canUpload
      ? '无上传操作权限'
      : viewModel.hasChild
      ? '上传本地照片'
      : '请先在主界面顶部搜索选定儿童';

  String _downloadTip(PhotoManagementViewModel viewModel) => !viewModel.canDownload
      ? '无下载操作权限'
      : viewModel.selectedPhoto != null
      ? '下载选中照片到本地'
      : '请先选择照片';

  String _deleteTip(PhotoManagementViewModel viewModel) => !viewModel.canDelete
      ? '无删除操作权限'
      : viewModel.selectedPhoto != null
      ? '删除选中照片'
      : '请先选择照片';

  /// 工具栏按钮（filled 主操作实心、次要操作描边；禁用时 tooltip 保留）。
  Widget _toolbarButton(ThemeData theme, {required IconData icon, required String label, required String tip, required bool enabled, required bool filled, required VoidCallback? onPressed}) {
    final button = filled
        ? FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return Tooltip(message: tip, child: button);
  }

  /// 照片区：装载中转圈；未选儿童/无照片空态；其余为照片卡片网格
  /// （单击选中、双击放大预览）。
  Widget _buildPhotoArea(ThemeData theme, PhotoManagementViewModel viewModel) {
    if (viewModel.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!viewModel.hasChild) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('请先在主界面顶部搜索选定儿童', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    if (viewModel.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('暂无照片，可拍照或上传本地照片', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.72),
      itemCount: viewModel.photos.length,
      itemBuilder: (context, index) => _buildPhotoCard(theme, viewModel, viewModel.photos[index]),
    );
  }

  /// 照片卡片：缩略图（缩略图缺失回退头像）+ 拍摄年龄 + 创建人；单击
  /// 选中/再点取消，选中态描边高亮 + 右上角勾选标记。
  Widget _buildPhotoCard(ThemeData theme, PhotoManagementViewModel viewModel, ChildPhoto photo) {
    final selected = photo.id != null && photo.id == viewModel.selectedId;
    return GestureDetector(
      onTap: photo.id == null ? null : () => viewModel.select(photo.id!),
      onDoubleTap: photo.id == null ? null : () => _previewPhoto(photo),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: selected ? 2 : 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPhotoImage(theme, photo),
                  // 选中标记（右上角勾选，底衬圆片保证在任意照片上可辨）
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: 0.9), shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _photoAgeText(photo),
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    photo.creatorName,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片缩略图：缩略图缺失（存量行）回退头像；解码失败/缺数据显示破图
  /// 占位。
  Widget _buildPhotoImage(ThemeData theme, ChildPhoto photo) {
    final bytes = _decodeBase64(photo.thumbBase64 ?? photo.avatarBase64);
    if (bytes == null) {
      return Center(child: Icon(Icons.broken_image_outlined, size: 36, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)));
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Center(child: Icon(Icons.broken_image_outlined, size: 36, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
    );
  }
}
