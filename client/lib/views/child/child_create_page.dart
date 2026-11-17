import 'package:client/utils/captured_photo.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/child/child_basic_info_form.dart';
import 'package:client/views/child/child_ext_info_form.dart';
import 'package:client/views/child/child_guardian_panel.dart';
import 'package:client/widgets/camera_capture_dialog.dart';
import 'package:client/widgets/child_pick_dialog.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童建档页（路由 /child/create）：无儿童列表的纯编辑界面。
///
/// 待编辑的儿童来自主界面顶部搜索选定的「当前儿童」上下文：进页时
/// 若 MainViewModel 中已有当前儿童则自动载入其整档（基本信息/扩展
/// 信息/监护人）并进入浏览态；未选定时从空态开始（仅有新增权限的
/// 账号自动进入新增录入态）。四个操作按钮常驻、按登录角色操作权限
/// 灰化（0201000001-新增/0201000002-修改/0201000003-保存/0201000004-
/// 删除）；三个 Tab 分别编辑基本信息/扩展信息/监护人，监护人行增删
/// 改不做权限控制、随整单保存。
class ChildCreatePage extends BasePage {
  const ChildCreatePage({super.key, required super.loginUser, required super.child});

  @override
  State<ChildCreatePage> createState() => _ChildCreatePageState();
}

class _ChildCreatePageState extends State<ChildCreatePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ChildCreateViewModel _viewModel;
  late final MainViewModel _mainViewModel;

  /// 正在载入的外部选定儿童 ID（防重入：载入过程中 MainViewModel 的
  /// 通知可能再次触发监听）。
  String? _syncingExternalId;

  /// 表单键：模式/目标档案变化时整体换新（新 GlobalKey 不会复用旧
  /// State，等效于普通 ValueKey 的重建语义，确保各表单控制器从最新
  /// 档案初始化；页面整单保存经这两个键访问表单校验与收集）。
  String? _formIdentity;
  GlobalKey<ChildBasicInfoFormState> _basicKey = GlobalKey(debugLabel: 'childBasicForm');
  GlobalKey<ChildExtInfoFormState> _extKey = GlobalKey(debugLabel: 'childExtForm');

  /// 模式/档案标识变化时换新表单键。
  void _ensureFormKeys(ChildCreateViewModel vm) {
    final identity = '${vm.mode.name}:${vm.currentChildId}';
    if (_formIdentity != identity) {
      _formIdentity = identity;
      _basicKey = GlobalKey(debugLabel: 'basic:$identity');
      _extKey = GlobalKey(debugLabel: 'ext:$identity');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Tab 切换时刷新（内容区为 IndexedStack，index 变更即切换显示）
    _tabController.addListener(_onTabChanged);
    _viewModel = context.read<ChildCreateViewModel>();
    _viewModel.addListener(_onViewModelChanged);
    // 主界面顶部搜索选定的儿童写入 MainViewModel.child 时，本页已挂载
    // 不会重建——监听上下文变化，把新选定儿童即时载入本页展示
    _mainViewModel = context.read<MainViewModel>();
    _mainViewModel.addListener(_onMainChildChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  /// 主界面顶部搜索选定新儿童（页面已打开）→ 载入该儿童整档并进入浏览态。
  ///
  /// 与本页自身写入（保存成功/查重选中后 setCurrentChild）以档案 ID 去重：
  /// ID 与该页当前档案一致时忽略，不会重复载入。
  void _onMainChildChanged() {
    final selectedId = _mainViewModel.child.id;
    if (selectedId.isEmpty) return;
    if (selectedId == _viewModel.currentChildId) return;
    if (selectedId == _syncingExternalId) return;
    _loadExternalChild(selectedId);
  }

  /// 载入外部选定的儿童档案；录入态（新增/修改）可能有未保存内容，
  /// 先确认再覆盖。
  Future<void> _loadExternalChild(String id) async {
    _syncingExternalId = id;
    try {
      if (!mounted) return;
      if (_viewModel.creating || _viewModel.editing) {
        final theme = Theme.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.transparent,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: GlassPanel(
                blur: 24,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('切换当前儿童', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text('当前有未保存的录入内容，浏览新选定的儿童将放弃这些内容。是否继续？', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
                          const SizedBox(width: 12),
                          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('继续')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        if (confirmed != true) return;
      }
      final ok = await _viewModel.selectChild(id);
      // 载入成功后切回基本信息 Tab，便于直接浏览
      if (ok && mounted) {
        _tabController.animateTo(0);
      }
    } finally {
      _syncingExternalId = null;
    }
  }

  /// Tab 切换落地时重建（动画过渡中的中间事件忽略）。
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  Future<void> _init() async {
    // await 前先取齐依赖（避免跨异步使用 BuildContext）
    final mainViewModel = _mainViewModel;
    await _viewModel.loadPermissions();
    // 主界面已选定当前儿童（顶部搜索写入的上下文）→ 自动载入整档进
    // 浏览态，默认展示基本信息/扩展信息/监护人（selectChild 内部的
    // initAddressFromChild 会按需加载省列表并完成五级区划回显；此处
    // 不可再重复调 getProvinces——重复拉取会生成新的 Province 对象，
    // 使已选中的省与 items 身份失配触发下拉断言）
    final currentChildId = mainViewModel.child.id;
    if (currentChildId.isNotEmpty) {
      await _viewModel.selectChild(currentChildId);
    }
    // 无修改/删除权限（无查询入口）、也未选定儿童 → 直接进入新增录入态
    //（仅有新增权限场景）
    if (!_viewModel.browsing && _viewModel.canCreate) {
      await _viewModel.startCreate();
    }
  }

  @override
  void dispose() {
    _mainViewModel.removeListener(_onMainChildChanged);
    _viewModel.removeListener(_onViewModelChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// VM 状态回调：错误弹 SnackBar（浮窗式）并立即清错防重复。
  void _onViewModelChanged() {
    final errorMsg = _viewModel.errorMsg;
    if (errorMsg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: '关闭', onPressed: ScaffoldMessenger.of(context).hideCurrentSnackBar),
        ),
      );
      _viewModel.clearError();
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 打开拍照对话框（基本信息 Tab 拍照区点击头像触发；浏览态由表单侧
  /// 禁用入口），确定后把 720×900 照片与 320×320 头像记为待保存结果。
  Future<void> _startCapture() async {
    final result = await CameraCaptureDialog.show(context);
    if (result != null && mounted) {
      _viewModel.setPendingPhoto(
        CapturedPhoto(photoBase64: result.photoBase64, avatarBase64: result.avatarBase64),
      );
    }
  }

  /// 移除头像：新增态（未入库）仅清除本次拍照；修改态删除当天全部拍照
  /// 记录并恢复显示历史头像（带确认）。
  Future<void> _removePhoto() async {
    if (_viewModel.currentChildId.isEmpty) {
      _viewModel.clearPendingPhoto();
      return;
    }
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
                  Text('移除今日拍照', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('将删除今天拍摄的全部记录，头像恢复显示为历史拍照；确定移除吗？', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('移除'),
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
    final ok = await _viewModel.removeTodayPhoto();
    if (ok && mounted) {
      _showToast('已移除今日拍照记录');
    }
  }

  /// 整单保存：依次校验基本/扩展 Tab，失败切到首个出错 Tab 并滚动定位；
  /// 保存前按「姓名+性别+出生日期」做重复建档检查——命中时弹相似儿童
  /// 列表确认（选择已有即转浏览该档案并写入全局当前儿童上下文，取消则
  /// 作为新儿童继续保存）；保存成功后自动把该儿童写入全局当前儿童
  /// 上下文（MainViewModel.child）。
  Future<void> _submit() async {
    // await 前先取齐依赖（避免跨异步使用 BuildContext）
    final mainViewModel = context.read<MainViewModel>();
    // 两个键在表单挂载后必然有 State；为空属异常兜底（重建间隙点击等）
    final basicState = _basicKey.currentState;
    final extState = _extKey.currentState;
    if (basicState == null || extState == null) {
      _showToast('表单尚未就绪，请稍候重试');
      return;
    }
    if (!basicState.validate()) {
      _tabController.animateTo(0);
      return;
    }
    if (!extState.validate()) {
      _tabController.animateTo(1);
      return;
    }
    final child = basicState.collect();
    final ext = extState.collectOrNull();

    // 重复建档检查：命中 → 相似儿童列表确认（取消=作为新儿童继续保存）
    final duplicates = await _viewModel.checkDuplicate(child);
    if (!mounted) return;
    if (duplicates.isNotEmpty) {
      final picked = await showChildPickDialog(
        context,
        duplicates,
        title: '发现同名同性别同出生日期的儿童',
        showCancelButton: true,
        cancelHint: '点击取消视为新儿童，将继续保存',
      );
      if (!mounted) return;
      if (picked != null) {
        // 用户确认与已有档案为同一儿童 → 转浏览该档案并写入当前儿童上下文
        await _viewModel.selectChild(picked.id);
        mainViewModel.setCurrentChild(picked);
        return;
      }
    }

    final ok = await _viewModel.save(child: child, ext: ext);
    if (ok) {
      // 保存成功 → 自动将新建/修改后的儿童写入全局当前儿童上下文
      final saved = _viewModel.child;
      if (saved != null) {
        mainViewModel.setCurrentChild(saved);
      }
      _showToast('保存成功');
    }
  }

  /// 删除当前档案（确认对话框）。
  Future<void> _deleteCurrent() async {
    final child = _viewModel.child;
    if (child == null) return;
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
                  Text('删除儿童档案', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                    '确定删除「${child.name}」的儿童档案吗？扩展信息与监护人将一并删除，操作不可恢复。',
                    style: theme.textTheme.bodyMedium,
                  ),
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
    if (confirmed == true) {
      final ok = await _viewModel.deleteCurrent();
      if (ok) {
        _showToast('删除成功');
      }
    }
  }

  /// 放弃录入（未载入档案时确认直接清空回空态）。
  Future<void> _cancelEdit() async {
    await _viewModel.cancelEdit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<ChildCreateViewModel>();
    final editing = vm.creating || vm.editing;
    // 模式/目标档案变化时换新表单键（须在用键构建表单前执行）
    _ensureFormKeys(vm);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildButtonBar(theme, vm, editing),
          const SizedBox(height: 12),
          Expanded(
            child: vm.loading
                ? const Center(child: CircularProgressIndicator())
                : GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              const Tab(text: '基本信息'),
                              const Tab(text: '扩展信息'),
                              Tab(text: '监护人（${vm.guardians.length}）'),
                            ],
                          ),
                          const Divider(height: 1),
                          const SizedBox(height: 16),
                          // 用 IndexedStack 而非 TabBarView：三个 Tab 表单
                          // 全部常驻挂载（TabBarView 懒构建，未访问过的 Tab
                          // 表单 State 不存在，整单保存时校验键会为空）；
                          // 各 Tab 顶部留 8px 内距，防首行浮动标签贴顶被裁
                          Expanded(
                            child: IndexedStack(
                              index: _tabController.index,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: ChildBasicInfoForm(
                                    key: _basicKey,
                                    viewModel: vm,
                                    editable: editing,
                                    onSubmit: editing ? _submit : null,
                                    onCapturePhoto: editing ? _startCapture : null,
                                    onRemovePhoto: editing ? _removePhoto : null,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: ChildExtInfoForm(
                                    key: _extKey,
                                    viewModel: vm,
                                    editable: editing,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: ChildGuardianPanel(viewModel: vm, editable: editing),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 按钮栏：新增/修改/保存/删除四个按钮常驻，按操作权限与当前模式
  /// 灰化（onPressed 置 null 即禁用），Tooltip 说明禁用原因——无权限
  /// 时灰化而非隐藏，便于用户感知功能存在与授权缺口。
  Widget _buildButtonBar(ThemeData theme, ChildCreateViewModel vm, bool editing) {
    final createReady = vm.canCreate && !editing; // 录入态中不可再点新增
    final updateReady = vm.canUpdate && vm.browsing; // 浏览态（已载入档案）才可进入修改
    final saveReady = vm.canSave && (vm.creating || vm.editing); // 保存独立授权，录入态才有效
    final deleteReady = vm.canDelete && vm.browsing;

    String saveTip;
    if (vm.creating || vm.editing) {
      saveTip = vm.canSave ? '保存儿童档案' : '无保存操作权限';
    } else {
      saveTip = '请先新增或载入儿童档案';
    }

    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: vm.canCreate ? '新增儿童档案' : '无新增操作权限',
              child: OutlinedButton.icon(
                onPressed: createReady ? () => _viewModel.startCreate() : null,
                icon: const Icon(Icons.add_outlined, size: 18),
                label: const Text('新增'),
              ),
            ),
            Tooltip(
              message: !vm.canUpdate ? '无修改操作权限' : (vm.browsing ? '修改当前儿童档案' : '请先新增或载入儿童档案'),
              child: OutlinedButton.icon(
                onPressed: updateReady ? () => _viewModel.startEdit() : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('修改'),
              ),
            ),
            Tooltip(
              message: saveTip,
              child: FilledButton.icon(
                onPressed: (saveReady && !vm.busy) ? _submit : null,
                icon: vm.busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                label: const Text('保 存'),
              ),
            ),
            if (editing)
              OutlinedButton.icon(
                onPressed: vm.busy ? null : _cancelEdit,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('取消'),
              ),
            Tooltip(
              message: !vm.canDelete ? '无删除操作权限' : (vm.browsing ? '删除当前儿童档案' : '请先新增或载入儿童档案'),
              child: OutlinedButton.icon(
                onPressed: (deleteReady && !vm.busy) ? _deleteCurrent : null,
                icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                label: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ),
            if (!editing && vm.child != null)
              Text(
                '浏览模式：${vm.child!.name}（点击【修改】编辑，【新增】建档）',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
          ],
        ),
      ),
    );
  }
}
