import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/child/child_basic_info_form.dart';
import 'package:client/views/child/child_ext_info_form.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/views/child/child_guardian_panel.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童建档页（路由 /child/create）：无儿童列表的纯编辑界面。
///
/// 顶部查询区（有修改/删除权限时显示）按姓名盲索引/就诊卡号/保健号
/// 检索并载入已有档案；四个操作按钮常驻、按登录角色操作权限灰化
/// （0201000001-新增/0201000002-修改/0201000003-保存/0201000004-删除）；
/// 三个 Tab 分别编辑基本信息/扩展信息/监护人，监护人行增删改不做权限
/// 控制、随整单保存。
class ChildCreatePage extends BasePage {
  const ChildCreatePage({super.key, required super.loginUser, required super.child});

  @override
  State<ChildCreatePage> createState() => _ChildCreatePageState();
}

class _ChildCreatePageState extends State<ChildCreatePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final ChildCreateViewModel _viewModel;

  final GlobalKey<ChildBasicInfoFormState> _basicKey = GlobalKey<ChildBasicInfoFormState>();
  final GlobalKey<ChildExtInfoFormState> _extKey = GlobalKey<ChildExtInfoFormState>();

  final _queryNameCtrl = TextEditingController();
  final _queryCardCtrl = TextEditingController();
  final _queryHealthCtrl = TextEditingController();
  ChildInfo? _selectedResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _viewModel = context.read<ChildCreateViewModel>();
    _viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await _viewModel.loadPermissions();
    await _viewModel.getProvinces();
    // 无修改/删除权限时无查询区，直接进入新增录入态（仅有新增权限场景）
    if (!_viewModel.showQueryArea && _viewModel.canCreate) {
      await _viewModel.startCreate();
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _tabController.dispose();
    _queryNameCtrl.dispose();
    _queryCardCtrl.dispose();
    _queryHealthCtrl.dispose();
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

  /// 检索本院儿童档案（查询区按钮）。
  Future<void> _search() async {
    final ok = await _viewModel.search(
      name: _queryNameCtrl.text.trim(),
      visitCardNo: _queryCardCtrl.text.trim(),
      healthNo: _queryHealthCtrl.text.trim(),
    );
    if (ok) {
      setState(() => _selectedResult = null);
    }
  }

  /// 整单保存：依次校验基本/扩展 Tab，失败切到首个出错 Tab 并滚动定位。
  Future<void> _submit() async {
    final basicOk = _basicKey.currentState?.validate() ?? true;
    if (!basicOk) {
      _tabController.animateTo(0);
      return;
    }
    final extOk = _extKey.currentState?.validate() ?? true;
    if (!extOk) {
      _tabController.animateTo(1);
      return;
    }
    final child = _basicKey.currentState!.collect();
    final ext = _extKey.currentState!.collectOrNull();
    final ok = await _viewModel.save(child: child, ext: ext);
    if (ok) {
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
        content: GlassPanel(
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.showQueryArea) ...[
            _buildQueryArea(theme, vm),
            const SizedBox(height: 12),
          ],
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
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                // 各 Tab 顶部留 8px 内距：outlined 输入框的
                                // 浮动标签会超出字段矩形上边缘约半个字高，
                                // 首行字段标签贴视口顶边会被裁剪
                                _keepAlive(
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ChildBasicInfoForm(
                                      key: Key('basic:${vm.mode.name}:${vm.currentChildId}'),
                                      viewModel: vm,
                                      editable: editing,
                                      onSubmit: editing ? _submit : null,
                                    ),
                                  ),
                                ),
                                _keepAlive(
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ChildExtInfoForm(
                                      key: Key('ext:${vm.mode.name}:${vm.currentChildId}'),
                                      viewModel: vm,
                                      editable: editing,
                                    ),
                                  ),
                                ),
                                _keepAlive(
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ChildGuardianPanel(viewModel: vm, editable: editing),
                                  ),
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

  /// TabBarView 子项保活（三个 Tab 的表单状态/校验键在整单保存时都
  /// 需要可用）。
  Widget _keepAlive(Widget child) {
    return _KeepAliveWidget(child: child);
  }

  /// 顶部查询区：姓名（盲索引精确匹配）/就诊卡号/保健号 + 检索结果下拉。
  Widget _buildQueryArea(ThemeData theme, ChildCreateViewModel vm) {
    final results = vm.searchResults;
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _queryField(theme, _queryNameCtrl, '姓名（精确匹配）', width: 220),
                _queryField(theme, _queryCardCtrl, '就诊卡号', width: 220),
                _queryField(theme, _queryHealthCtrl, '保健号', width: 220),
                FilledButton.tonalIcon(
                  onPressed: vm.loading ? null : _search,
                  icon: const Icon(Icons.search_outlined, size: 18),
                  label: const Text('查询'),
                ),
                Text(
                  '姓名为精确匹配，可组合查询',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 480,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('search-result-${results.map((e) => e.id).join('-')}'),
                  initialValue: _selectedResult?.id,
                  isExpanded: true,
                  items: results
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(_resultLabel(c), style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  hint: Text('请选择要载入的儿童档案（${results.length} 条）', style: theme.textTheme.bodyMedium),
                  decoration: childGlassDecoration(theme, '检索结果'),
                  style: theme.textTheme.bodyMedium,
                  onChanged: (id) async {
                    if (id == null) return;
                    ChildInfo? matched;
                    for (final c in results) {
                      if (c.id == id) {
                        matched = c;
                        break;
                      }
                    }
                    setState(() => _selectedResult = matched);
                    await _viewModel.selectChild(id);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _resultLabel(ChildInfo c) {
    final sex = c.sex == '1' ? '男' : (c.sex == '2' ? '女' : '');
    final card = (c.visitCardNo == null || c.visitCardNo!.isEmpty) ? '' : ' · ${c.visitCardNo}';
    return '${c.name} $sex ${c.birthDate}$card';
  }

  Widget _queryField(ThemeData theme, TextEditingController controller, String label, {double width = 240}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        decoration: childGlassDecoration(theme, label),
        style: theme.textTheme.bodyMedium,
        onFieldSubmitted: (_) => _search(),
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
                icon: const Icon(Icons.child_care_outlined, size: 18),
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
              TextButton(
                onPressed: vm.busy ? null : _cancelEdit,
                child: const Text('取消'),
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

/// TabBarView 子项保活容器（AutomaticKeepAliveClientMixin）。
class _KeepAliveWidget extends StatefulWidget {
  const _KeepAliveWidget({required this.child});

  final Widget child;

  @override
  State<_KeepAliveWidget> createState() => _KeepAliveWidgetState();
}

class _KeepAliveWidgetState extends State<_KeepAliveWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
