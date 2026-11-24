import 'package:client/models/current_child.dart';
import 'package:client/utils/dict_options.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 孤独症初筛记录表页（路由 /asd/initialScreening）：11 个月龄 TAB
/// （3/6/8/12/18/24/30/36 月龄与 4/5/6 岁），每个 TAB 独立展示与编辑
/// 该月龄的初筛记录（同一儿童同一时段至多一条）。已做初筛的 TAB 标签
/// 右上方显示红点；打开页面按当前儿童实足年龄自动切换 TAB（需求窗口
/// 口径见 [InitialScreeningViewModel]）；未做初筛的月龄默认进入新增
/// 状态。按钮按操作权限 0301000001-新增/0301000002-修改/0301000003-
/// 保存/0301000004-删除/0301000005-打印灰化控制；【打印】弹出菜单含
/// 打印初筛记录表/打印转诊单两项（打印功能待后续开发）。
class InitialScreeningPage extends BasePage {
  const InitialScreeningPage({super.key, required super.loginUser, required super.child});

  @override
  State<InitialScreeningPage> createState() => _InitialScreeningPageState();
}

class _InitialScreeningPageState extends State<InitialScreeningPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: screeningTabs.length, vsync: this);

  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听。
  late final InitialScreeningViewModel _viewModel;

  late final MainViewModel _mainViewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<InitialScreeningViewModel>();
    _viewModel.addListener(_onViewModelChanged);
    _mainViewModel = context.read<MainViewModel>();
    _mainViewModel.addListener(_onMainChildChanged);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewModel.loadPermissions();
      _viewModel.syncChild(_mainViewModel.hasCurrentChild ? _mainViewModel.child : null);
      _ensureActiveScaleItems();
    });
  }

  @override
  void dispose() {
    // 实例来自 Provider 全局注入，这里只移除监听，不要 viewModel.dispose()
    _mainViewModel.removeListener(_onMainChildChanged);
    _viewModel.removeListener(_onViewModelChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// 主界面「当前儿童」变化 → 同步进 VM（未选定则为 null，整页清空）。
  void _onMainChildChanged() {
    _viewModel.syncChild(_mainViewModel.hasCurrentChild ? _mainViewModel.child : null);
  }

  /// VM 变化：消费自动切 TAB（每儿童一次，消费后 VM 返回 null）+ 错误提示。
  void _onViewModelChanged() {
    if (!mounted) return;
    final autoMonth = _viewModel.autoTabMonth;
    if (autoMonth != null) {
      final index = screeningTabs.indexWhere((tab) => tab.$1 == autoMonth);
      if (index >= 0) {
        _viewModel.markAutoTabConsumed();
        _tabController.animateTo(index);
      }
    }
    final theme = Theme.of(context);
    if (_viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_viewModel.errorMsg!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(label: '关闭', textColor: theme.colorScheme.onPrimary, onPressed: _viewModel.clearError),
        ),
      );
      // 提示后立即清空，避免同一错误重复弹出
      _viewModel.clearError();
    }
  }

  /// 切换 TAB 后懒加载当前月龄的预警征象条目。
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureActiveScaleItems();
  }

  void _ensureActiveScaleItems() {
    final month = screeningTabs[_tabController.index].$1;
    _viewModel.ensureScaleItems(month);
  }

  /// 打印菜单项占位（打印功能待后续开发）。
  void _printPlaceholder(String label) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label功能开发中，敬请期待', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<InitialScreeningViewModel>();
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainer,
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          _buildToolbar(theme, viewModel),
          Expanded(
            child: viewModel.hasChild
                ? Column(
                    children: [
                      // 窄屏下 11 个 TAB 标签水平触控滚动（isScrollable）
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final (month, label) in screeningTabs) _MonthTab(label: label, hasRecord: viewModel.hasRecord(month)),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            for (final (month, _) in screeningTabs) _MonthFormPage(key: ValueKey('month-$month'), month: month, viewModel: _viewModel, loginUser: widget.loginUser, onPrint: _printPlaceholder),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      viewModel.child == null ? '请先在主界面顶部搜索选定儿童' : '当前儿童未建档或已失效，请重新搜索选定',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 顶部工具栏：标题 + 当前儿童摘要 + 刷新 + 打印菜单。
  Widget _buildToolbar(ThemeData theme, InitialScreeningViewModel viewModel) {
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
          Icon(Icons.fact_check_outlined, size: 20, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(
            '初筛记录表',
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: child == null
                ? Text('未选定儿童——请先在主界面顶部搜索选定', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8)))
                : Text(
                    '${child.name}　${child.gender}　${_summaryAge(child)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(width: 12),
          _toolbarButton(
            theme,
            icon: Icons.refresh_outlined,
            label: '刷新',
            enabled: viewModel.hasChild && !viewModel.busy,
            onPressed: () => _viewModel.reload(),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '打印',
            enabled: viewModel.canPrint && viewModel.hasChild,
            style: IconButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.08),
            ),
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.print_outlined, size: 18, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 4),
                Text('打印', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ],
            ),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'record', child: Text('打印初筛记录表')),
              PopupMenuItem<String>(value: 'referral', child: Text('打印转诊单')),
            ],
            onSelected: (value) => _printPlaceholder(value == 'record' ? '打印初筛记录表' : '打印转诊单'),
          ),
        ],
      ),
    );
  }

  String _summaryAge(CurrentChild child) {
    final text = child.actualAge;
    return text.isEmpty ? '' : '　$text';
  }

  Widget _toolbarButton(ThemeData theme, {required IconData icon, required String label, required bool enabled, required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        side: BorderSide(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.4)),
        backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.06),
      ),
    );
  }
}

/// TAB 标签：月龄文案 + 已做初筛时右上角红点标记。
class _MonthTab extends StatelessWidget {
  const _MonthTab({required this.label, required this.hasRecord});

  final String label;

  final bool hasRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tab(
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          if (hasRecord)
            // 已做初筛红点：标签右上方 4px 圆点
            Positioned(
              top: -2,
              right: -6,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个月龄 TAB 的表单页：浏览（已做初筛）/ 新增（未做初筛默认）/ 修改
/// 三态，每页状态独立保存（TabBarView + KeepAlive，切 TAB 不丢录入）。
class _MonthFormPage extends StatefulWidget {
  const _MonthFormPage({super.key, required this.month, required this.viewModel, required this.loginUser, required this.onPrint});

  final int month;

  final InitialScreeningViewModel viewModel;

  final LoginUser loginUser;

  /// 打印菜单占位回调（页级工具栏统一弹出）。
  final void Function(String label) onPrint;

  @override
  State<_MonthFormPage> createState() => _MonthFormPageState();
}

enum _FormMode { browse, add, edit }

class _MonthFormPageState extends State<_MonthFormPage> with AutomaticKeepAliveClientMixin {
  static const String _noneAbnormal = '未见异常';
  static const String _languageDisorder = '语言功能障碍或倒退';
  static const String _socialDisorder = '社会交往能力障碍或倒退';

  final TextEditingController _checkDateCtrl = TextEditingController();
  final TextEditingController _referralHospCtrl = TextEditingController();
  final TextEditingController _referralDeptCtrl = TextEditingController();

  /// 转诊医院/科室字典数据项（自由输入 + 下拉选择并存，值存 ITEM_VALUE）。
  List<DictItem>? _referralHospItems;
  List<DictItem>? _referralDeptItems;

  _FormMode _mode = _FormMode.add;

  /// 已按哪条数据水合（儿童 ID + 记录 ID；变化即重填表单）。
  String? _hydratedKey;

  DateTime? _checkDate;

  /// 预警征象选中集合（条目名称；含互斥的「未见异常」时仅此一项）。
  final Set<String> _warningSelection = {};

  /// 语言功能和社会交往能力询问结果选中集合。
  final Set<String> _languageSelection = {};

  String _hasReferral = '0';

  String? _doctorId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    _loadDictItems();
    _hydrate(force: true);
    // 打开 TAB 即懒加载本页预警征象条目（相邻 TAB 由页级 TabBar 切换
    // 监听触发；KeepAlive 页初始未挂载的不触发也无妨，进入时触发）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.viewModel.ensureScaleItems(widget.month);
    });
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _checkDateCtrl.dispose();
    _referralHospCtrl.dispose();
    _referralDeptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDictItems() async {
    try {
      final hospItems = await DictOptions.instance.itemsOf('0201001');
      final deptItems = await DictOptions.instance.itemsOf('0201002');
      if (mounted) {
        setState(() {
          _referralHospItems = hospItems;
          _referralDeptItems = deptItems;
        });
      }
    } catch (e, st) {
      // 字典未配置/加载失败按空处理（转诊名称仍可自由输入）
      LogHelper.error('client:InitialScreeningPage._loadDictItems', e, st);
      if (mounted) {
        setState(() {
          _referralHospItems = const [];
          _referralDeptItems = const [];
        });
      }
    }
  }

  /// VM 变化：记录装载完成 / 儿童切换 / 医生候选就绪时按需重填表单。
  void _onViewModelChanged() {
    if (!mounted) return;
    _hydrate(force: false);
    // 新增态且尚未选医生：候选就绪后选默认（登录用户优先，无则首位）
    if (_mode != _FormMode.browse && _doctorId == null && widget.viewModel.doctorsLoaded) {
      final fallback = _defaultDoctorId();
      if (fallback != null) {
        setState(() => _doctorId = fallback);
      }
    }
  }

  /// 默认检查医生：登录用户在候选中优先，否则候选首位。
  String? _defaultDoctorId() {
    final doctors = widget.viewModel.doctors;
    if (doctors.isEmpty) return null;
    for (final d in doctors) {
      if (d.id == widget.loginUser.id) return d.id;
    }
    return doctors.first.id;
  }

  /// 表单水合：儿童或记录变化时重填（浏览态填记录值，无记录进新增态）。
  ///
  /// 打印水合键区分「该月龄尚无记录」与「有记录」；保存成功/删除成功后
  /// 记录集合变化，键随之变化触发重填。
  void _hydrate({required bool force}) {
    final vm = widget.viewModel;
    final record = vm.recordOf(widget.month);
    final key = '${vm.child?.id ?? ''}|${record?.id ?? 'new'}';
    if (!force && key == _hydratedKey) {
      return;
    }
    _hydratedKey = key;
    if (record != null) {
      _applyRecord(record);
    } else {
      _resetForAdd();
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 浏览态：按已保存记录填充。
  void _applyRecord(InitialScreening record) {
    _mode = _FormMode.browse;
    _checkDate = DateTime.tryParse(record.checkDate);
    _checkDateCtrl.text = record.checkDate;
    _warningSelection
      ..clear()
      ..addAll(record.warningSignResult.split('、').where((e) => e.isNotEmpty));
    _languageSelection
      ..clear()
      ..addAll(record.languageSocialCommunicationResult.split('、').where((e) => e.isNotEmpty));
    _hasReferral = record.hasReferral;
    _referralHospCtrl.text = record.hasReferral == '1' ? record.referralHospName : '';
    _referralDeptCtrl.text = record.referralDeptName ?? '';
    _doctorId = record.doctorId;
  }

  /// 新增态：清空并给检查日期默认今天（业务时间口径）、医生默认候选。
  void _resetForAdd() {
    _mode = _FormMode.add;
    final now = widget.viewModel.now();
    _checkDate = DateTime(now.year, now.month, now.day);
    _checkDateCtrl.text = _fmtDate(_checkDate!);
    _warningSelection.clear();
    _languageSelection.clear();
    _hasReferral = '0';
    _referralHospCtrl.clear();
    _referralDeptCtrl.clear();
    _doctorId = _defaultDoctorId();
  }

  /// 新增（按钮）：清空当前 TAB 表单进入新增态（该月龄已有记录时保存
  /// 将整体覆盖）。
  void _startAdd() {
    setState(_resetForAdd);
  }

  /// 修改（按钮）：进入编辑态。
  void _startEdit() {
    final record = widget.viewModel.recordOf(widget.month);
    if (record == null) return;
    setState(() => _mode = _FormMode.edit);
  }

  /// 保存：客户端校验 → 组装记录 → VM 保存（成功后记录变化触发重填回
  /// 浏览态）。
  Future<void> _save() async {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void fail(String message) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError)),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final child = vm.child;
    if (child == null || child.id.isEmpty) {
      fail('请先选定儿童');
      return;
    }
    final checkDate = _checkDate;
    if (checkDate == null) {
      fail('请选择检查日期');
      return;
    }
    final actual = vm.actualAgePartsFor(checkDate);
    if (actual == null) {
      fail('检查日期应晚于儿童出生日期');
      return;
    }
    if (_warningSelection.isEmpty) {
      fail('请选择预警征象筛查结果');
      return;
    }
    if (_languageSelection.isEmpty) {
      fail('请选择语言功能和社会交往能力询问结果');
      return;
    }
    final doctor = vm.doctors.where((d) => d.id == _doctorId).firstOrNull;
    if (doctor == null) {
      fail('请选择检查医生');
      return;
    }
    final referralHospName = _referralHospCtrl.text.trim();
    if (_hasReferral == '1' && referralHospName.isEmpty) {
      fail('有转诊时须填写转诊医院名称');
      return;
    }

    final corrected = vm.correctedAgePartsFor(checkDate);
    final record = InitialScreening(
      childId: child.id,
      checkDate: _fmtDate(checkDate),
      ageYear: actual.years,
      ageMonth: actual.months,
      ageDay: actual.days,
      correctedAgeYear: corrected?.years,
      correctedAgeMonth: corrected?.months,
      correctedAgeDay: corrected?.days,
      checkMonth: widget.month,
      warningSignResult: _warningSelection.join('、'),
      languageSocialCommunicationResult: _languageSelection.join('、'),
      checkResult: _derivedCheckResult(),
      hasReferral: _hasReferral,
      referralHospId: _dictIdOf(_referralHospItems, referralHospName),
      referralHospName: _hasReferral == '1' ? referralHospName : '无',
      referralDeptId: _dictIdOf(_referralDeptItems, _referralDeptCtrl.text.trim()),
      referralDeptName: _hasReferral == '1' && _referralDeptCtrl.text.trim().isNotEmpty ? _referralDeptCtrl.text.trim() : null,
      doctorId: doctor.id,
      doctorName: doctor.userName,
      creatorId: '',
      creatorName: '',
      hospId: '',
      hospName: '',
    );
    final ok = await vm.saveRecord(record);
    if (!mounted) return;
    if (ok) {
      // 记录集合已变化，下一次水合回浏览态（展示保存后的权威值）
      _hydratedKey = null;
      _hydrate(force: false);
    }
  }

  /// 删除（带确认）。
  Future<void> _confirmDelete() async {
    final vm = widget.viewModel;
    final record = vm.recordOf(widget.month);
    if (record == null) return;
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
                  Text('删除初筛记录', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('将删除该儿童「${_tabLabel(widget.month)}」时段的初筛记录，删除后不可恢复。确定删除吗？', style: theme.textTheme.bodyMedium),
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
    final ok = await widget.viewModel.deleteRecord(widget.month);
    if (ok && mounted) {
      // 记录已删除：进新增态（默认状态）
      _hydratedKey = null;
      _hydrate(force: false);
    }
  }

  /// 初筛结果自动推导：预警征象与语言/社会询问结果均为「未见异常」→
  /// 未见异常；任一存在异常项 → 异常。
  String _derivedCheckResult() {
    final normal = _warningSelection.length == 1 && _warningSelection.contains(_noneAbnormal) && _languageSelection.length == 1 && _languageSelection.contains(_noneAbnormal);
    return normal ? _noneAbnormal : '异常';
  }

  /// 文本反查字典数据项 ID（自由输入不在字典中时为 null）。
  String? _dictIdOf(List<DictItem>? items, String value) {
    if (items == null || value.isEmpty) return null;
    for (final item in items) {
      if (item.itemValue == value) return item.id;
    }
    return null;
  }

  String _fmtDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _tabLabel(int month) {
    for (final (m, label) in screeningTabs) {
      if (m == month) return label;
    }
    return '$month月龄';
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final editable = _mode != _FormMode.browse;
    final record = vm.recordOf(widget.month);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme, vm, record),
              const SizedBox(height: 12),
              _buildFieldGrid(theme, vm, editable),
              const SizedBox(height: 12),
              _buildWarningSigns(theme, vm, editable),
              const SizedBox(height: 12),
              _buildLanguageSocial(theme, editable),
              const SizedBox(height: 12),
              _buildReferralSection(theme, editable),
            ],
          ),
        ),
      ),
    );
  }

  /// 表单头：模式提示 + 新增/修改/保存/删除按钮行。
  Widget _buildHeader(ThemeData theme, InitialScreeningViewModel vm, InitialScreening? record) {
    final modeText = switch (_mode) {
      _FormMode.browse => '浏览（已做初筛）',
      _FormMode.add => record == null ? '新增（该月龄尚未初筛）' : '新增（保存后将覆盖已有记录）',
      _FormMode.edit => '修改',
    };
    Widget actionButton({required IconData icon, required String label, required bool enabled, required VoidCallback onPressed, Color? color}) {
      return FilledButton.tonalIcon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(foregroundColor: color ?? theme.colorScheme.primary),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${_tabLabel(widget.month)}　$modeText',
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        actionButton(
          icon: Icons.add_outlined,
          label: '新增',
          enabled: vm.canCreate && vm.hasChild && !vm.busy,
          onPressed: _startAdd,
        ),
        actionButton(
          icon: Icons.edit_outlined,
          label: '修改',
          enabled: record != null && vm.canUpdate && !vm.busy,
          onPressed: _startEdit,
        ),
        actionButton(
          icon: Icons.save_outlined,
          label: '保存',
          enabled: _mode != _FormMode.browse && vm.canSave && vm.hasChild && !vm.busy,
          onPressed: _save,
        ),
        actionButton(
          icon: Icons.delete_outlined,
          label: '删除',
          color: theme.colorScheme.error,
          enabled: record != null && vm.canDelete && !vm.busy,
          onPressed: _confirmDelete,
        ),
        if (vm.busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  /// 基础字段网格：检查日期/实足年龄/纠正年龄/初筛结果/有无转诊/转诊
  /// 医院/转诊科室/检查医生（窄屏 Wrap 自动换行，宽屏两列）。
  Widget _buildFieldGrid(ThemeData theme, InitialScreeningViewModel vm, bool editable) {
    final actual = _checkDate == null ? null : vm.actualAgePartsFor(_checkDate!);
    final corrected = _checkDate == null ? null : vm.correctedAgePartsFor(_checkDate!);
    final ageText = actual == null ? '' : _fmtAge(actual);
    final correctedText = corrected == null ? '不适用' : _fmtAge(corrected);

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _fieldBox(
          theme,
          label: '检查日期',
          required: editable,
          child: TextFormField(
            controller: _checkDateCtrl,
            readOnly: true,
            enabled: editable,
            style: theme.textTheme.bodyMedium,
            decoration: _decoration(theme, '检查日期', required: editable),
            onTap: editable
                ? () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _checkDate ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                      helpText: '选择检查日期',
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        _checkDate = picked;
                        _checkDateCtrl.text = _fmtDate(picked);
                      });
                    }
                  }
                : null,
          ),
        ),
        _fieldBox(
          theme,
          label: '实足年龄',
          child: _displayField(theme, ageText.isEmpty ? '——' : ageText),
        ),
        _fieldBox(
          theme,
          label: '纠正年龄',
          child: _displayField(theme, correctedText),
        ),
        _fieldBox(
          theme,
          label: '初筛结果',
          required: true,
          child: DropdownButtonFormField<String>(
            // 初筛结果由预警征象与询问结果自动推导，界面只读展示；经
            // ValueKey 随推导值重建（initialValue 仅首次生效）
            key: ValueKey('result-${_derivedCheckResult()}'),
            initialValue: _derivedCheckResult(),
            items: const [
              DropdownMenuItem(value: _noneAbnormal, child: Text(_noneAbnormal)),
              DropdownMenuItem(value: '异常', child: Text('异常')),
            ],
            onChanged: null,
            style: theme.textTheme.bodyMedium,
            decoration: _decoration(theme, '初筛结果', required: true),
          ),
        ),
        _fieldBox(
          theme,
          label: '有无转诊',
          required: true,
          child: DropdownButtonFormField<String>(
            // ValueKey 随外部赋值重建：initialValue 仅首次生效（3.33+
            // value 参数已弃用），选择后 onChanged 更新状态触发重建回显
            key: ValueKey('referral-$_hasReferral'),
            initialValue: _hasReferral,
            items: const [
              DropdownMenuItem(value: '0', child: Text('无')),
              DropdownMenuItem(value: '1', child: Text('有')),
            ],
            enabled: editable,
            onChanged: editable
                ? (v) {
                    setState(() {
                      _hasReferral = v ?? '0';
                      // 切回无转诊时清空转诊医院/科室
                      if (_hasReferral == '0') {
                        _referralHospCtrl.clear();
                        _referralDeptCtrl.clear();
                      }
                    });
                  }
                : null,
            style: theme.textTheme.bodyMedium,
            decoration: _decoration(theme, '有无转诊', required: true),
          ),
        ),
        _fieldBox(
          theme,
          label: '转诊医院名称',
          required: _hasReferral == '1',
          child: _referralCombo(
            theme,
            controller: _referralHospCtrl,
            items: _referralHospItems,
            enabled: editable && _hasReferral == '1',
            hint: _hasReferral == '1' ? '下拉选择或自由输入' : '无转诊时不可填',
          ),
        ),
        _fieldBox(
          theme,
          label: '转诊科室名称',
          child: _referralCombo(
            theme,
            controller: _referralDeptCtrl,
            items: _referralDeptItems,
            enabled: editable && _hasReferral == '1',
            hint: _hasReferral == '1' ? '下拉选择或自由输入' : '无转诊时不可填',
          ),
        ),
        _fieldBox(
          theme,
          label: '检查医生',
          required: true,
          child: vm.doctors.isEmpty
              ? _displayField(theme, vm.doctorsLoaded ? '当前科室无医生候选' : '加载中...')
              : DropdownButtonFormField<String>(
                  // ValueKey 随外部赋值重建（水合/默认医生），见「有无转诊」注
                  key: ValueKey('doctor-$_doctorId'),
                  initialValue: _doctorId != null && vm.doctors.any((d) => d.id == _doctorId) ? _doctorId : null,
                  items: [
                    for (final d in vm.doctors)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(d.userName, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                  enabled: editable,
                  onChanged: editable ? (v) => setState(() => _doctorId = v) : null,
                  hint: Text('请选择检查医生', style: theme.textTheme.bodyMedium),
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '检查医生', required: true),
                ),
        ),
      ],
    );
  }

  /// 预警征象筛查结果：未见异常（互斥）+ 当月龄条目多选。
  Widget _buildWarningSigns(ThemeData theme, InitialScreeningViewModel vm, bool editable) {
    final items = vm.scaleItemsOf(widget.month);
    final loading = vm.scaleItemsLoading(widget.month);
    return _sectionBox(
      theme,
      title: '预警征象筛查结果',
      required: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items == null && loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('预警征象条目加载中...', style: theme.textTheme.bodySmall),
                ],
              ),
            )
          else if (items != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '预警征象字典未配置该月龄条目（SCALE_WSCMBD 待录入），可选择【未见异常】或联系维护人员',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _choiceChip(
                  theme,
                  label: _noneAbnormal,
                  selected: _warningSelection.contains(_noneAbnormal),
                  enabled: editable,
                  onSelected: () => _toggleWarning(_noneAbnormal),
                ),
                for (final item in items ?? const <WscmbdItem>[])
                  _choiceChip(
                    theme,
                    label: item.itemName,
                    selected: _warningSelection.contains(item.itemName),
                    enabled: editable,
                    onSelected: () => _toggleWarning(item.itemName),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// 预警征象互斥选择：选「未见异常」清条目，选任一条目清「未见异常」。
  void _toggleWarning(String name) {
    setState(() {
      if (name == _noneAbnormal) {
        _warningSelection
          ..clear()
          ..add(_noneAbnormal);
        return;
      }
      _warningSelection.remove(_noneAbnormal);
      if (!_warningSelection.add(name)) {
        _warningSelection.remove(name);
      }
    });
  }

  /// 语言功能和社会交往能力询问结果：未见异常（互斥）+ 两项异常多选。
  Widget _buildLanguageSocial(ThemeData theme, bool editable) {
    return _sectionBox(
      theme,
      title: '语言功能和社会交往能力询问结果',
      required: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _choiceChip(
            theme,
            label: _noneAbnormal,
            selected: _languageSelection.contains(_noneAbnormal),
            enabled: editable,
            onSelected: () => _toggleLanguage(_noneAbnormal),
          ),
          _choiceChip(
            theme,
            label: _languageDisorder,
            selected: _languageSelection.contains(_languageDisorder),
            enabled: editable,
            onSelected: () => _toggleLanguage(_languageDisorder),
          ),
          _choiceChip(
            theme,
            label: _socialDisorder,
            selected: _languageSelection.contains(_socialDisorder),
            enabled: editable,
            onSelected: () => _toggleLanguage(_socialDisorder),
          ),
        ],
      ),
    );
  }

  /// 询问结果互斥选择（逻辑同预警征象）。
  void _toggleLanguage(String name) {
    setState(() {
      if (name == _noneAbnormal) {
        _languageSelection
          ..clear()
          ..add(_noneAbnormal);
        return;
      }
      _languageSelection.remove(_noneAbnormal);
      if (!_languageSelection.add(name)) {
        _languageSelection.remove(name);
      }
    });
  }

  /// 转诊信息段落标题（有无转诊下拉在字段网格内，此处仅组合说明）。
  Widget _buildReferralSection(ThemeData theme, bool editable) {
    return _sectionBox(
      theme,
      title: '转诊说明',
      child: Text(
        _hasReferral == '1' ? '已选择转诊：请填写转诊医院与转诊科室（可下拉选择字典项或自由输入）。' : '未转诊：转诊医院/科室不可填写。初筛异常时请选择转诊并填写转诊信息。',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
    );
  }

  // ---------------- 通用小组件 ----------------

  String _fmtAge(({int years, int months, int days}) parts) => [
    if (parts.years > 0) '${parts.years}岁',
    if (parts.months > 0) '${parts.months}个月',
    if (parts.days > 0 || (parts.years == 0 && parts.months == 0)) '${parts.days}天',
  ].join();

  Widget _fieldBox(ThemeData theme, {required String label, required Widget child, bool required = false}) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: label,
              style: theme.textTheme.bodySmall,
              children: [
                if (required)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _sectionBox(ThemeData theme, {required String title, required Widget child, bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: title,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            children: [
              if (required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _displayField(ThemeData theme, String text) {
    return TextFormField(
      initialValue: text,
      readOnly: true,
      enabled: false,
      style: theme.textTheme.bodyMedium,
      decoration: _decoration(theme, null),
    );
  }

  /// 转诊名称组合框：DropdownMenu 支持自由输入 + 下拉选择（enableFilter
  /// 输入过滤；禁用态沿用控制器文本展示）。
  Widget _referralCombo(ThemeData theme, {required TextEditingController controller, required List<DictItem>? items, required bool enabled, required String hint}) {
    final entries = [
      for (final item in items ?? const <DictItem>[]) DropdownMenuEntry<String>(value: item.itemValue, label: item.itemValue),
    ];
    return DropdownMenu<String>(
      controller: controller,
      enabled: enabled,
      enableFilter: true,
      expandedInsets: EdgeInsets.zero,
      initialSelection: controller.text.isNotEmpty && entries.any((e) => e.value == controller.text) ? controller.text : null,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        surfaceTintColor: WidgetStatePropertyAll(theme.colorScheme.surface),
      ),
      textStyle: theme.textTheme.bodyMedium,
      hintText: hint,
      trailingIcon: Icon(Icons.arrow_drop_down_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
      dropdownMenuEntries: entries,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15)),
        ),
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _choiceChip(ThemeData theme, {required String label, required bool selected, required bool enabled, required VoidCallback onSelected}) {
    return FilterChip(
      label: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)),
      selected: selected,
      onSelected: enabled ? (_) => onSelected() : null,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      side: BorderSide(color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }

  InputDecoration _decoration(ThemeData theme, String? label, {bool required = false}) {
    OutlineInputBorder glassBorder(ThemeData theme, Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      enabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      focusedBorder: glassBorder(theme, theme.colorScheme.primary),
      disabledBorder: glassBorder(theme, theme.colorScheme.outlineVariant.withValues(alpha: 0.15)),
    );
  }
}
