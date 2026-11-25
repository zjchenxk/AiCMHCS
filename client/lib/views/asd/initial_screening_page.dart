import 'package:client/main.dart';
import 'package:client/models/current_child.dart';
import 'package:client/services/holiday_service.dart';
import 'package:client/services/initial_screening_service.dart';
import 'package:client/utils/asd_check_flow.dart';
import 'package:client/utils/dict_options.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/next_check_date.dart';
import 'package:client/view_models/asd/initial_screening_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:client/widgets/guidance_template_dialog.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 孤独症初筛记录表页（路由 /asd/initialScreening）：11 个月龄 TAB
/// （3/6/8/12/18/24/30/36 月龄与 4/5/6 岁），每个 TAB 独立展示与编辑
/// 该月龄的初筛记录（同一儿童同一时段至多一条）。已做初筛的 TAB 标签
/// 右上方红点；实足年龄命中的 TAB 标签红字醒目且打开页面自动切换；
/// 未做初筛的月龄默认进入新增状态。操作模式与儿童建档一致（浏览态
/// 开放新增/修改，录入态二者灰化并出现【取消】）。
///
/// 表单布局对照服务规范表 2~4，每行 3 个组件：检查日期/实足年龄/纠正
/// 年龄 → 预警征象筛查/语言功能与社会交往能力询问/初筛结果（三项均为
/// 多选或单选下拉，未见异常与异常项互斥）→ 指导建议（全宽多行，附
/// 【选择模板】与【获取DeepSeek AI建议】）→ 有无转诊/转诊医院/转诊科室
/// → 下次检查日期/检查医生/操作人员。下次检查日期在初筛未见异常时按
/// 出生日期推下一年龄段自动计算并顺延周末与法定节假日（见
/// [NextCheckDateUtil]），异常时清空，手动选择不受限制。保存校验
/// 初筛结果与两项询问结果匹配、异常必转诊、转诊医院非空、检查医生
/// 非空；服务端同步联动转诊/预约/检查汇总三表。
class InitialScreeningPage extends BasePage {
  const InitialScreeningPage({super.key, required super.loginUser, required super.child});

  @override
  State<InitialScreeningPage> createState() => _InitialScreeningPageState();
}

class _InitialScreeningPageState extends State<InitialScreeningPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: screeningTabs.length, vsync: this);

  late final InitialScreeningViewModel _viewModel;

  late final MainViewModel _mainViewModel;

  /// 已应用「自动切 TAB」的儿童 ID（每儿童每进页只应用一次）。
  String? _autoTabAppliedChildId;

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
      _tryApplyAutoTab();
      _ensureActiveScaleItems();
    });
  }

  @override
  void dispose() {
    _mainViewModel.removeListener(_onMainChildChanged);
    _viewModel.removeListener(_onViewModelChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onMainChildChanged() {
    _viewModel.syncChild(_mainViewModel.hasCurrentChild ? _mainViewModel.child : null);
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    _tryApplyAutoTab();
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
      _viewModel.clearError();
    }
  }

  void _tryApplyAutoTab() {
    final childId = _viewModel.child?.id ?? '';
    if (childId.isEmpty || _autoTabAppliedChildId == childId) {
      return;
    }
    final month = _viewModel.computeAutoTabMonth();
    _autoTabAppliedChildId = childId;
    if (month == null) return;
    final index = screeningTabs.indexWhere((tab) => tab.$1 == month);
    if (index >= 0 && index != _tabController.index) {
      _tabController.animateTo(index);
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureActiveScaleItems();
  }

  void _ensureActiveScaleItems() {
    final month = screeningTabs[_tabController.index].$1;
    _viewModel.ensureScaleItems(month);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<InitialScreeningViewModel>();
    final theme = Theme.of(context);
    final ageMonth = viewModel.computeAutoTabMonth();
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
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final (month, label) in screeningTabs) _MonthTab(label: label, hasRecord: viewModel.hasRecord(month), highlight: month == ageMonth),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            for (final (month, _) in screeningTabs) _MonthFormPage(key: ValueKey('month-$month'), month: month, viewModel: _viewModel, loginUser: widget.loginUser),
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

  /// 顶部工具栏：标题 + 当前儿童摘要 + 刷新。
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
          OutlinedButton.icon(
            onPressed: viewModel.hasChild && !viewModel.busy ? () => _viewModel.reload() : null,
            icon: const Icon(Icons.refresh_outlined, size: 18),
            label: const Text('刷新'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              side: BorderSide(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.4)),
              backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }

  String _summaryAge(CurrentChild child) {
    final text = child.actualAge;
    return text.isEmpty ? '' : '　$text';
  }
}

/// TAB 标签：月龄文案（实足年龄命中时段红字醒目）+ 已做初筛红点。
class _MonthTab extends StatelessWidget {
  const _MonthTab({required this.label, required this.hasRecord, required this.highlight});

  final String label;

  final bool hasRecord;

  final bool highlight;

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
            child: Text(
              label,
              style: highlight ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold) : theme.textTheme.bodyMedium,
            ),
          ),
          if (hasRecord)
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

enum _FormMode { browse, add, edit }

/// 单个月龄 TAB 的表单页（浏览/新增/修改三态，KeepAlive 保录入）。
class _MonthFormPage extends StatefulWidget {
  const _MonthFormPage({super.key, required this.month, required this.viewModel, required this.loginUser});

  final int month;

  final InitialScreeningViewModel viewModel;

  final LoginUser loginUser;

  @override
  State<_MonthFormPage> createState() => _MonthFormPageState();
}

class _MonthFormPageState extends State<_MonthFormPage> with AutomaticKeepAliveClientMixin {
  static const String _noneAbnormal = AsdCheckFlow.noneAbnormal;
  static const String _languageDisorder = '语言功能障碍或倒退';
  static const String _socialDisorder = '社会交往能力障碍或倒退';
  static const String _resultAbnormal = AsdCheckFlow.abnormal;

  final TextEditingController _checkDateCtrl = TextEditingController();
  final TextEditingController _actualAgeCtrl = TextEditingController();
  final TextEditingController _correctedAgeCtrl = TextEditingController();
  final TextEditingController _guidanceCtrl = TextEditingController();
  final TextEditingController _referralHospCtrl = TextEditingController();
  final TextEditingController _referralDeptCtrl = TextEditingController();
  final TextEditingController _nextCheckDateCtrl = TextEditingController();
  final TextEditingController _operatorCtrl = TextEditingController();

  List<DictItem>? _referralHospItems;
  List<DictItem>? _referralDeptItems;

  /// 本院法定节假日（下次检查日期顺延用；首次进入懒加载一次）。
  List<BaseHoliday>? _holidays;
  bool _holidaysLoading = false;

  _FormMode _mode = _FormMode.add;

  String? _hydratedKey;

  DateTime? _checkDate;
  DateTime? _nextCheckDate;

  final Set<String> _warningSelection = {_noneAbnormal};
  final Set<String> _languageSelection = {_noneAbnormal};

  /// 初筛结果（下拉：未见异常/异常；默认未见异常）。
  String _checkResult = _noneAbnormal;

  String _hasReferral = '0';

  String? _doctorId;

  bool _aiBusy = false;

  InitialScreeningService get _screeningService => getIt<InitialScreeningService>();
  HolidayService get _holidayService => getIt<HolidayService>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    _loadDictItems();
    _loadHolidays();
    _hydrate(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.viewModel.ensureScaleItems(widget.month);
    });
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _checkDateCtrl.dispose();
    _actualAgeCtrl.dispose();
    _correctedAgeCtrl.dispose();
    _guidanceCtrl.dispose();
    _referralHospCtrl.dispose();
    _referralDeptCtrl.dispose();
    _nextCheckDateCtrl.dispose();
    _operatorCtrl.dispose();
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
      LogHelper.error('client:InitialScreeningPage._loadDictItems', e, st);
      if (mounted) {
        setState(() {
          _referralHospItems = const [];
          _referralDeptItems = const [];
        });
      }
    }
  }

  /// 懒加载本院法定节假日（顺延判断用；失败按空处理，仅影响节假日顺延）。
  Future<void> _loadHolidays() async {
    if (_holidays != null || _holidaysLoading) return;
    _holidaysLoading = true;
    try {
      final list = await _holidayService.queryAll();
      if (mounted) setState(() => _holidays = list);
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningPage._loadHolidays', e, st);
      if (mounted) setState(() => _holidays = const []);
    } finally {
      _holidaysLoading = false;
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    _hydrate(force: false);
    if (_mode != _FormMode.browse && _doctorId == null && widget.viewModel.doctorsLoaded) {
      final fallback = _defaultDoctorId();
      if (fallback != null) {
        setState(() => _doctorId = fallback);
      }
    }
  }

  /// 默认检查医生：仅当登录用户本身是同科室医生候选时默认选中，否则
  /// 为空（需求 11）。
  String? _defaultDoctorId() {
    for (final d in widget.viewModel.doctors) {
      if (d.id == widget.loginUser.id) return d.id;
    }
    return null;
  }

  void _hydrate({required bool force}) {
    final vm = widget.viewModel;
    final record = vm.recordOf(widget.month);
    final key = '${vm.child?.id ?? ''}|${record?.id ?? 'new'}';
    if (!force && key == _hydratedKey) return;
    _hydratedKey = key;
    if (record != null) {
      _applyRecord(record);
    } else {
      _resetForAdd();
    }
    if (mounted) setState(() {});
  }

  void _applyRecord(InitialScreening record) {
    _mode = _FormMode.browse;
    _checkDate = DateTime.tryParse(record.checkDate);
    _checkDateCtrl.text = record.checkDate;
    _warningSelection
      ..clear()
      ..addAll(record.warningSignResult.split('、').where((e) => e.isNotEmpty));
    if (_warningSelection.isEmpty) _warningSelection.add(_noneAbnormal);
    _languageSelection
      ..clear()
      ..addAll(record.languageSocialCommunicationResult.split('、').where((e) => e.isNotEmpty));
    if (_languageSelection.isEmpty) _languageSelection.add(_noneAbnormal);
    _checkResult = record.checkResult.isEmpty ? _noneAbnormal : record.checkResult;
    _guidanceCtrl.text = record.guidance ?? '';
    _hasReferral = record.hasReferral;
    _referralHospCtrl.text = record.hasReferral == '1' ? record.referralHospName : '';
    _referralDeptCtrl.text = record.referralDeptName ?? '';
    _nextCheckDate = DateTime.tryParse(record.nextCheckDate ?? '');
    _nextCheckDateCtrl.text = record.nextCheckDate ?? '';
    _doctorId = record.doctorId;
    _refreshDisplayFields();
  }

  /// 新增态：检查日期默认今天（业务时间口径）、两项询问与初筛结果默认
  /// 未见异常、指导建议给默认文本、下次检查日期按当前时段推算。
  void _resetForAdd() {
    _mode = _FormMode.add;
    final now = widget.viewModel.now();
    _checkDate = DateTime(now.year, now.month, now.day);
    _checkDateCtrl.text = NextCheckDateUtil.formatDate(_checkDate!);
    _warningSelection
      ..clear()
      ..add(_noneAbnormal);
    _languageSelection
      ..clear()
      ..add(_noneAbnormal);
    _checkResult = _noneAbnormal;
    _guidanceCtrl.text = AsdCheckFlow.guidanceFor(_checkResult);
    _hasReferral = '0';
    _referralHospCtrl.clear();
    _referralDeptCtrl.clear();
    _doctorId = _defaultDoctorId();
    _recomputeNextCheckDate();
    _refreshDisplayFields();
  }

  void _refreshDisplayFields() {
    final vm = widget.viewModel;
    final record = vm.recordOf(widget.month);
    final actual = _checkDate == null ? null : vm.actualAgePartsFor(_checkDate!);
    final corrected = _checkDate == null ? null : vm.correctedAgePartsFor(_checkDate!);
    _actualAgeCtrl.text = actual == null ? '' : _fmtAge(actual);
    // 非早产儿/超矫正窗口：纠正年龄留空（不显示「不适用」）
    _correctedAgeCtrl.text = corrected == null ? '' : _fmtAge(corrected);
    final browsing = _mode == _FormMode.browse && record != null;
    _operatorCtrl.text = browsing ? record.creatorName : widget.loginUser.userName;
  }

  void _startAdd() => setState(_resetForAdd);

  void _startEdit() {
    final record = widget.viewModel.recordOf(widget.month);
    if (record == null) return;
    setState(() {
      _mode = _FormMode.edit;
      _refreshDisplayFields();
    });
  }

  void _cancelEdit() {
    final record = widget.viewModel.recordOf(widget.month);
    setState(() {
      if (record != null) {
        _applyRecord(record);
      } else {
        _resetForAdd();
      }
    });
  }

  /// 下次检查日期自动重算：结果=异常时清空；未见异常时按出生日期推下一年龄段
  /// 并顺延周末/法定节假日（已到 6 岁末段则留空）。
  void _recomputeNextCheckDate() {
    if (_checkResult == _resultAbnormal) {
      _nextCheckDate = null;
      _nextCheckDateCtrl.clear();
      return;
    }
    final child = widget.viewModel.child;
    if (child == null || child.id.isEmpty) {
      _nextCheckDate = null;
      _nextCheckDateCtrl.clear();
      return;
    }
    final computed = NextCheckDateUtil.compute(
      birthDate: child.birthDate,
      currentMonth: widget.month,
      holidays: _holidays ?? const [],
    );
    _nextCheckDate = computed;
    _nextCheckDateCtrl.text = computed == null ? '' : NextCheckDateUtil.formatDate(computed);
  }

  /// 初筛结果变更：按结果联动其余字段（指导建议/有无转诊/下次检查日期）。
  void _onCheckResultChanged(String? value) {
    setState(() {
      _checkResult = value ?? _noneAbnormal;
      _applyCheckResultEffects();
    });
  }

  /// 初筛结果的级联效果（需求 3/4）：
  /// - 未见异常 → 指导建议置默认文本、有无转诊置「无」（清空转诊医院/科室）；
  /// - 异常 → 指导建议清空、有无转诊置「有」（转诊医院/科室可填）；
  /// 两种情况都重算下次检查日期（异常清空）。
  void _applyCheckResultEffects() {
    final guidance = AsdCheckFlow.guidanceFor(_checkResult);
    if (guidance.isEmpty) {
      _guidanceCtrl.clear();
    } else {
      _guidanceCtrl.text = guidance;
    }
    _hasReferral = AsdCheckFlow.referralFlagFor(_checkResult);
    if (_hasReferral == '0') {
      _referralHospCtrl.clear();
      _referralDeptCtrl.clear();
    }
    _recomputeNextCheckDate();
  }

  /// 两项询问结果变更后自动推导初筛结果（需求 1/2）：
  /// - 两项均为「未见异常」→ 初筛结果「未见异常」；
  /// - 任一项存在非「未见异常」的选中项 → 初筛结果「异常」。
  /// 结果发生变化时继续触发 [_applyCheckResultEffects] 级联。
  void _syncResultFromSelections() {
    final nextResult = AsdCheckFlow.deriveResult(warningSigns: _warningSelection, languageSocial: _languageSelection);
    if (nextResult == _checkResult) return;
    _checkResult = nextResult;
    _applyCheckResultEffects();
  }

  /// 检查日期变更：刷新年龄展示并重算下次检查日期。
  void _onCheckDateChanged(DateTime picked) {
    setState(() {
      _checkDate = picked;
      _checkDateCtrl.text = NextCheckDateUtil.formatDate(picked);
      _refreshDisplayFields();
      _recomputeNextCheckDate();
    });
  }

  /// 选择模板：打开模板对话框，选定回填指导建议。
  Future<void> _pickGuidanceTemplate() async {
    final picked = await GuidanceTemplateDialog.show(context, service: _screeningService);
    if (picked == null || !mounted) return;
    setState(() => _guidanceCtrl.text = picked);
  }

  /// 获取 DeepSeek AI 建议（服务端调用，Key 不外泄）。
  Future<void> _fetchAiGuidance() async {
    final vm = widget.viewModel;
    final child = vm.child;
    if (child == null || child.id.isEmpty) return;
    setState(() => _aiBusy = true);
    final theme = Theme.of(context);
    try {
      final text = await _screeningService.aiGuidance(
        month: widget.month,
        sex: child.gender == '女' ? '2' : '1',
        warningSignResult: _warningSelection.join('、'),
        languageSocialResult: _languageSelection.join('、'),
      );
      if (!mounted) return;
      setState(() => _guidanceCtrl.text = text);
    } catch (e, st) {
      LogHelper.error('client:InitialScreeningPage._fetchAiGuidance', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), ''),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onError),
            ),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// 保存：校验（12.1~12.5）→ 组装记录 → VM 保存。
  Future<void> _save() async {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void fail(String message) {
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
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
    // 12.1/12.2：初筛结果与两项询问结果匹配
    final warningNormal = _warningSelection.length == 1 && _warningSelection.contains(_noneAbnormal);
    final languageNormal = _languageSelection.length == 1 && _languageSelection.contains(_noneAbnormal);
    if (warningNormal && languageNormal && _checkResult != _noneAbnormal) {
      fail('初筛结果应为未见异常，请检查确认');
      return;
    }
    if ((!warningNormal || !languageNormal) && _checkResult != _resultAbnormal) {
      fail('初筛结果应为异常，请检查确认');
      return;
    }
    // 12.3：异常必须转诊
    if (_checkResult == _resultAbnormal && _hasReferral != '1') {
      fail('初筛阳性，必须转诊到县级妇幼保健机构进行复筛');
      return;
    }
    // 12.4：有转诊须填转诊医院
    final referralHospName = _referralHospCtrl.text.trim();
    if (_hasReferral == '1' && referralHospName.isEmpty) {
      fail('转诊医院不能为空');
      return;
    }
    // 12.5：检查医生非空
    final doctor = vm.doctors.where((d) => d.id == _doctorId).firstOrNull;
    if (doctor == null) {
      fail('检查医生不能为空');
      return;
    }

    final corrected = vm.correctedAgePartsFor(checkDate);
    final record = InitialScreening(
      childId: child.id,
      checkDate: NextCheckDateUtil.formatDate(checkDate),
      ageYear: actual.years,
      ageMonth: actual.months,
      ageDay: actual.days,
      correctedAgeYear: corrected?.years,
      correctedAgeMonth: corrected?.months,
      correctedAgeDay: corrected?.days,
      checkMonth: widget.month,
      warningSignResult: _warningSelection.join('、'),
      languageSocialCommunicationResult: _languageSelection.join('、'),
      checkResult: _checkResult,
      guidance: _guidanceCtrl.text.trim().isEmpty ? null : _guidanceCtrl.text.trim(),
      hasReferral: _hasReferral,
      referralHospId: _dictIdOf(_referralHospItems, referralHospName),
      referralHospName: _hasReferral == '1' ? referralHospName : '无',
      referralDeptId: _dictIdOf(_referralDeptItems, _referralDeptCtrl.text.trim()),
      referralDeptName: _hasReferral == '1' && _referralDeptCtrl.text.trim().isNotEmpty ? _referralDeptCtrl.text.trim() : null,
      nextCheckDate: _nextCheckDate == null ? null : NextCheckDateUtil.formatDate(_nextCheckDate!),
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
      _hydratedKey = null;
      _hydrate(force: false);
    }
  }

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
                  Text(
                    '将删除该儿童「${NextCheckDateUtil.tabLabelOf(widget.month)}」时段的初筛记录，删除后不可恢复。确定删除吗？',
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
    if (confirmed != true || !mounted) return;
    final ok = await widget.viewModel.deleteRecord(widget.month);
    if (ok && mounted) {
      _hydratedKey = null;
      _hydrate(force: false);
    }
  }

  /// 打印菜单（锚定按钮弹出，两项为占位）。
  Future<void> _showPrintMenu(BuildContext buttonContext) async {
    final theme = Theme.of(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(box.localToGlobal(Offset.zero, ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(value: 'record', child: Text('打印初筛记录表')),
        PopupMenuItem<String>(value: 'referral', child: Text('打印转诊单')),
      ],
    );
    if (selected == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${selected == 'record' ? '打印初筛记录表' : '打印转诊单'}功能开发中，敬请期待',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
          ),
          backgroundColor: theme.colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String? _dictIdOf(List<DictItem>? items, String value) {
    if (items == null || value.isEmpty) return null;
    for (final item in items) {
      if (item.itemValue == value) return item.id;
    }
    return null;
  }

  String _fmtAge(({int years, int months, int days}) parts) => [
    if (parts.years > 0) '${parts.years}岁',
    if (parts.months > 0) '${parts.months}个月',
    if (parts.days > 0 || (parts.years == 0 && parts.months == 0)) '${parts.days}天',
  ].join();

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
              const SizedBox(height: 16),
              _responsiveRow([
                _dateField(theme, editable),
                _readonlyField(theme, controller: _actualAgeCtrl, label: '实足年龄'),
                _readonlyField(theme, controller: _correctedAgeCtrl, label: '纠正年龄'),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                _multiSelectField(
                  theme,
                  label: '预警征象筛查',
                  enabled: editable,
                  summary: _warningSelection.join('、'),
                  onTap: _pickWarningSigns,
                ),
                _multiSelectField(
                  theme,
                  label: '语言功能与社会交往能力询问',
                  enabled: editable,
                  summary: _languageSelection.join('、'),
                  onTap: _pickLanguageSocial,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('checkResult-$_checkResult'),
                  initialValue: _checkResult,
                  // 菜单项 Text 显式带 bodyMedium（含主题色）：DropdownButton
                  // 禁用时会把 DefaultTextStyle 置 disabledColor，裸 Text 会跟着
                  // 变灰；显式样式可保持与儿童建档一致的黑色文字
                  items: [
                    DropdownMenuItem(
                      value: _noneAbnormal,
                      child: Text(_noneAbnormal, style: theme.textTheme.bodyMedium),
                    ),
                    DropdownMenuItem(
                      value: _resultAbnormal,
                      child: Text(_resultAbnormal, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                  // 浏览态只置 onChanged 为 null（勿显式 enabled:false——那会
                  // 用 disabledColor 变灰，与儿童建档浏览样式不一致）
                  onChanged: editable ? _onCheckResultChanged : null,
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '初筛结果'),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _guidanceCtrl,
                enabled: editable,
                minLines: 3,
                maxLines: 6,
                style: theme.textTheme.bodyMedium,
                decoration: _decoration(theme, '指导建议'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: editable ? _pickGuidanceTemplate : null,
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('选择模板'),
                  ),
                  OutlinedButton.icon(
                    onPressed: editable && !_aiBusy ? _fetchAiGuidance : null,
                    icon: _aiBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('获取DeepSeek AI建议'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _responsiveRow([
                DropdownButtonFormField<String>(
                  key: ValueKey('referral-$_hasReferral'),
                  initialValue: _hasReferral,
                  // 同上：菜单项显式带 bodyMedium，避免浏览态被 disabledColor 染灰
                  items: [
                    DropdownMenuItem(
                      value: '0',
                      child: Text('无', style: theme.textTheme.bodyMedium),
                    ),
                    DropdownMenuItem(
                      value: '1',
                      child: Text('有', style: theme.textTheme.bodyMedium),
                    ),
                  ],
                  // 浏览态仅置 onChanged 为 null（保持黑色文字，同儿童建档）
                  onChanged: editable
                      ? (v) {
                          setState(() {
                            _hasReferral = v ?? '0';
                            if (_hasReferral == '0') {
                              _referralHospCtrl.clear();
                              _referralDeptCtrl.clear();
                            }
                          });
                        }
                      : null,
                  style: theme.textTheme.bodyMedium,
                  decoration: _decoration(theme, '有无转诊'),
                ),
                _referralCombo(
                  theme,
                  controller: _referralHospCtrl,
                  items: _referralHospItems,
                  editable: editable,
                  enabled: editable && _hasReferral == '1',
                  label: '转诊医院',
                  hint: '下拉选择或自由输入',
                ),
                _referralCombo(
                  theme,
                  controller: _referralDeptCtrl,
                  items: _referralDeptItems,
                  editable: editable,
                  enabled: editable && _hasReferral == '1',
                  label: '转诊科室',
                  hint: '下拉选择或自由输入',
                ),
              ]),
              const SizedBox(height: 12),
              _responsiveRow([
                _nextCheckDateField(theme, editable),
                _doctorField(theme, vm, editable),
                _readonlyField(theme, controller: _operatorCtrl, label: '操作人员'),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// 表单头：仅操作按钮（无月龄标签与模式提示），打印样式与其他按钮
  /// 一致。
  Widget _buildHeader(ThemeData theme, InitialScreeningViewModel vm, InitialScreening? record) {
    final browsing = _mode == _FormMode.browse;
    final editing = _mode != _FormMode.browse;
    final createReady = vm.canCreate && browsing && vm.hasChild && !vm.busy;
    final updateReady = vm.canUpdate && browsing && record != null && !vm.busy;
    final saveReady = vm.canSave && editing && vm.hasChild && !vm.busy;
    final deleteReady = vm.canDelete && browsing && record != null && !vm.busy;
    final printReady = vm.canPrint && browsing && record != null && !vm.busy;

    Widget actionButton({required IconData icon, required String label, required bool enabled, required String tip, required VoidCallback onPressed, Color? color}) {
      return Tooltip(
        message: tip,
        child: FilledButton.tonalIcon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(foregroundColor: color ?? theme.colorScheme.primary),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        actionButton(
          icon: Icons.add_outlined,
          label: '新增',
          enabled: createReady,
          tip: vm.canCreate ? '新增初筛记录' : '无新增操作权限',
          onPressed: _startAdd,
        ),
        actionButton(
          icon: Icons.edit_outlined,
          label: '修改',
          enabled: updateReady,
          tip: !vm.canUpdate ? '无修改操作权限' : (record != null ? '修改初筛记录' : '该月龄尚未初筛，请直接录入'),
          onPressed: _startEdit,
        ),
        actionButton(
          icon: Icons.save_outlined,
          label: '保存',
          enabled: saveReady,
          tip: vm.canSave ? (editing ? '保存初筛记录' : '请先点击【新增】或【修改】') : '无保存操作权限',
          onPressed: _save,
        ),
        if (editing)
          OutlinedButton.icon(
            onPressed: vm.busy ? null : _cancelEdit,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('取消'),
          ),
        actionButton(
          icon: Icons.delete_outlined,
          label: '删除',
          enabled: deleteReady,
          tip: !vm.canDelete ? '无删除操作权限' : (record != null ? '删除初筛记录' : '该月龄尚未初筛'),
          onPressed: _confirmDelete,
          color: theme.colorScheme.error,
        ),
        // 打印：与新增/修改/保存/删除同款按钮，点击锚定弹出菜单
        Tooltip(
          message: !vm.canPrint ? '无打印操作权限' : (record != null ? '打印初筛记录表/转诊单' : '该月龄尚未初筛'),
          child: Builder(
            builder: (buttonContext) => FilledButton.tonalIcon(
              onPressed: printReady ? () => _showPrintMenu(buttonContext) : null,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('打印'),
              style: FilledButton.styleFrom(foregroundColor: theme.colorScheme.primary),
            ),
          ),
        ),
        if (vm.busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  /// 宽屏每行 3 个组件，窄屏纵向堆叠。
  Widget _responsiveRow(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: fields[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              fields[i],
            ],
          ],
        );
      },
    );
  }

  Widget _dateField(ThemeData theme, bool editable) {
    return TextFormField(
      controller: _checkDateCtrl,
      readOnly: true,
      enabled: editable,
      style: theme.textTheme.bodyMedium,
      decoration: _decoration(theme, '检查日期'),
      onTap: editable
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _checkDate ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                helpText: '选择检查日期',
              );
              if (picked != null && mounted) _onCheckDateChanged(picked);
            }
          : null,
    );
  }

  /// 下次检查日期：可手动选择（不受周末/节假日限制）；结果=异常时置灰
  /// 并清空（自动推导）。
  Widget _nextCheckDateField(ThemeData theme, bool editable) {
    final enabled = editable && _checkResult != _resultAbnormal;
    return TextFormField(
      controller: _nextCheckDateCtrl,
      readOnly: true,
      enabled: enabled,
      style: theme.textTheme.bodyMedium,
      decoration: _decoration(theme, '下次检查日期').copyWith(
        suffixIcon: enabled && _nextCheckDateCtrl.text.isNotEmpty
            ? IconButton(
                tooltip: '按规则重算',
                icon: const Icon(Icons.autorenew_outlined, size: 18),
                onPressed: () => setState(_recomputeNextCheckDate),
              )
            : null,
      ),
      onTap: enabled
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _nextCheckDate ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
                helpText: '选择下次检查日期（手动选择不受周末/节假日限制）',
              );
              if (picked != null && mounted) {
                setState(() {
                  _nextCheckDate = picked;
                  _nextCheckDateCtrl.text = NextCheckDateUtil.formatDate(picked);
                });
              }
            }
          : null,
    );
  }

  Widget _readonlyField(ThemeData theme, {required TextEditingController controller, required String label}) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: false,
      style: theme.textTheme.bodyMedium,
      decoration: _decoration(theme, label),
    );
  }

  Widget _doctorField(ThemeData theme, InitialScreeningViewModel vm, bool editable) {
    if (vm.doctors.isEmpty) {
      return TextFormField(
        initialValue: vm.doctorsLoaded ? '当前科室无医生候选' : '加载中...',
        readOnly: true,
        enabled: false,
        style: theme.textTheme.bodyMedium,
        decoration: _decoration(theme, '检查医生'),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('doctor-$_doctorId'),
      initialValue: _doctorId != null && vm.doctors.any((d) => d.id == _doctorId) ? _doctorId : null,
      items: [
        for (final d in vm.doctors)
          DropdownMenuItem(
            value: d.id,
            child: Text(d.userName, style: theme.textTheme.bodyMedium),
          ),
      ],
      // 浏览态仅置 onChanged 为 null（保持黑色文字，同儿童建档）
      onChanged: editable ? (v) => setState(() => _doctorId = v) : null,
      hint: Text('请选择检查医生', style: theme.textTheme.bodyMedium),
      style: theme.textTheme.bodyMedium,
      decoration: _decoration(theme, '检查医生'),
    );
  }

  /// 多选下拉字段（仿输入框）：显示已选摘要，点击打开多选选择器。
  Widget _multiSelectField(ThemeData theme, {required String label, required bool enabled, required String summary, required VoidCallback onTap}) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          isEmpty: summary.isEmpty,
          decoration: _decoration(theme, label).copyWith(
            suffixIcon: Icon(Icons.arrow_drop_down_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          child: Text(
            summary.isEmpty ? '请选择$label' : summary,
            // 浏览态也保持黑色文字（与儿童建档浏览样式一致）
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// 预警征象多选选择器（未见异常与条目互斥；条目多选）。
  Future<void> _pickWarningSigns() async {
    final items = widget.viewModel.scaleItemsOf(widget.month) ?? const <WscmbdItem>[];
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _MultiSelectDialog(
        title: '预警征象筛查',
        hint: items.isEmpty ? 'SCALE_WSCMBD 未配置该月龄条目，仅可选【未见异常】' : '【未见异常】与其余条目互斥；条目可多选',
        options: [_noneAbnormal, for (final item in items) item.itemName],
        selected: Set.of(_warningSelection),
        exclusiveValue: _noneAbnormal,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _warningSelection
        ..clear()
        ..addAll(result);
      if (_warningSelection.isEmpty) _warningSelection.add(_noneAbnormal);
      _syncResultFromSelections();
    });
  }

  /// 语言功能和社会交往能力询问多选选择器（同互斥口径）。
  Future<void> _pickLanguageSocial() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _MultiSelectDialog(
        title: '语言功能与社会交往能力询问',
        hint: '【未见异常】与另两项互斥；两项异常可多选',
        options: const [_noneAbnormal, _languageDisorder, _socialDisorder],
        selected: Set.of(_languageSelection),
        exclusiveValue: _noneAbnormal,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _languageSelection
        ..clear()
        ..addAll(result);
      if (_languageSelection.isEmpty) _languageSelection.add(_noneAbnormal);
      _syncResultFromSelections();
    });
  }

  /// 转诊医院/科室组合框。浏览态用只读文本框展示（DropdownMenu 的禁用态
  /// 会改用 disabledColor 变灰，与儿童建档浏览样式不一致）；录入态用
  /// DropdownMenu（自由输入 + 字典下拉），有转诊时可用。
  Widget _referralCombo(
    ThemeData theme, {
    required TextEditingController controller,
    required List<DictItem>? items,
    required bool editable,
    required bool enabled,
    required String label,
    required String hint,
  }) {
    if (!editable) {
      return TextFormField(
        controller: controller,
        readOnly: true,
        enabled: false,
        style: theme.textTheme.bodyMedium,
        decoration: _decoration(theme, label),
      );
    }
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
      label: Text(label, style: theme.textTheme.bodyMedium),
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

  InputDecoration _decoration(ThemeData theme, String? label) {
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

/// 通用多选选择器（毛玻璃）：复选框逐项勾选，[exclusiveValue]（未见
/// 异常）与其余项互斥；空选不允许确定（至少一项）。
class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({required this.title, required this.hint, required this.options, required this.selected, required this.exclusiveValue});

  final String title;

  final String hint;

  final List<String> options;

  final Set<String> selected;

  /// 互斥项（选中即清空其他；选中其他即清空该项）。
  final String exclusiveValue;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _selected = Set.of(widget.selected);

  void _toggle(String value, bool checked) {
    setState(() {
      if (!checked) {
        _selected.remove(value);
        return;
      }
      if (value == widget.exclusiveValue) {
        _selected
          ..clear()
          ..add(value);
        return;
      }
      _selected
        ..remove(widget.exclusiveValue)
        ..add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
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
                    Icon(Icons.checklist_outlined, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('选择${widget.title}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(widget.hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in widget.options)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(option),
                          onChanged: (checked) => _toggle(option, checked ?? false),
                          title: Text(option, style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(_selected),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
