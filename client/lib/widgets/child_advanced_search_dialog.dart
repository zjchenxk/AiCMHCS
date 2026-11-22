import 'package:client/main.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/high_risk_factor_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/risk_color.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:common/model.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 高级搜索对话框（主界面顶部「高级搜索」入口，独立组件文件）：多条件
/// 「与」组合查询本院儿童档案（服务端分页），支持建档/出生日期区间、
/// 性别、姓名/就诊卡号/证件号码/联系电话/监护人姓名、孕周/体重数值区间
/// 与高危因素多选（候选取本院 BASE_HIGH_RISK_FACTOR 字典，「任一命中」
/// ——儿童保存过所选因素中任意一个即命中，见 CHILD_HIGH_RISK_FACTOR）。
///
/// 结果行单击选中（高亮）、双击直接选定；底部「确定」返回选中儿童，
/// 由调用方写入 MainViewModel 当前儿童上下文（setCurrentChild）。文本
/// 条件均为精确匹配（姓名/证件号码/联系电话/监护人姓名走服务端盲索引，
/// 密文列不支持模糊查询）；允许全空条件查询（相当于分页浏览全院档案）。
Future<ChildInfo?> showChildAdvancedSearchDialog(BuildContext context, {ChildService? service, HighRiskFactorService? highRiskFactorService}) {
  return showDialog<ChildInfo>(
    context: context,
    builder: (dialogContext) => _ChildAdvancedSearchDialog(service: service, highRiskFactorService: highRiskFactorService),
  );
}

class _ChildAdvancedSearchDialog extends StatefulWidget {
  const _ChildAdvancedSearchDialog({this.service, this.highRiskFactorService});

  /// 查询服务覆写（测试注入用；缺省经服务定位器获取）。
  final ChildService? service;

  /// 高危因素字典服务覆写（测试注入用；缺省经服务定位器获取）。
  final HighRiskFactorService? highRiskFactorService;

  @override
  State<_ChildAdvancedSearchDialog> createState() => _ChildAdvancedSearchDialogState();
}

class _ChildAdvancedSearchDialogState extends State<_ChildAdvancedSearchDialog> with SingleTickerProviderStateMixin {
  /// 每页条数（与后端默认分页口径一致）。
  static const int _pageSize = 20;

  late final TabController _tabController;

  final _checkFromCtrl = TextEditingController();
  final _checkToCtrl = TextEditingController();
  final _birthFromCtrl = TextEditingController();
  final _birthToCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _certCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _guardianCtrl = TextEditingController();
  final _weekFromCtrl = TextEditingController();
  final _weekToCtrl = TextEditingController();
  final _weightFromCtrl = TextEditingController();
  final _weightToCtrl = TextEditingController();

  /// 性别条件（''-全部 / '1'-男 / '2'-女）。
  String _sex = '';

  /// 性别下拉字段键（重置条件时还原下拉显示值）。
  final _sexFieldKey = GlobalKey<FormFieldState<String>>();

  /// 已选高危因素 ID 集合（空集=不过滤；跨查询保留）。
  Set<String> _selectedFactorIds = <String>{};

  /// 本院高危因素字典（首次打开选择器时懒加载，已按五色→编码→名称排序）。
  List<BaseHighRiskFactor>? _factors;

  bool _factorsLoading = false;

  String? _factorsError;

  HighRiskFactorService get _highRiskFactorService => widget.highRiskFactorService ?? getIt<HighRiskFactorService>();

  List<ChildInfo> _children = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;

  /// 是否已执行过查询（区分「未查询」与「查询无结果」两种空态）。
  bool _queried = false;
  String? _errorMsg;
  ChildInfo? _selected;

  List<TextEditingController> get _allControllers => [
    _checkFromCtrl,
    _checkToCtrl,
    _birthFromCtrl,
    _birthToCtrl,
    _nameCtrl,
    _cardCtrl,
    _certCtrl,
    _phoneCtrl,
    _guardianCtrl,
    _weekFromCtrl,
    _weekToCtrl,
    _weightFromCtrl,
    _weightToCtrl,
  ];

  ChildService get _childService => widget.service ?? getIt<ChildService>();

  /// 本院字典按展示口径排序：五色（绿→黄→橙→红→紫）在前、未设置颜色
  /// 最后，同色内按编码、名称升序（与互斥规则表单下拉同风格）。
  List<BaseHighRiskFactor> _sortedFactors(List<BaseHighRiskFactor> factors) {
    final colorOrder = {for (var i = 0; i < BaseHighRiskFactor.riskColors.length; i++) BaseHighRiskFactor.riskColors[i]: i};
    final last = BaseHighRiskFactor.riskColors.length;
    return [...factors]..sort((a, b) {
      final ca = colorOrder[a.riskColor] ?? last;
      final cb = colorOrder[b.riskColor] ?? last;
      if (ca != cb) return ca - cb;
      final code = a.riskFactorCode.compareTo(b.riskFactorCode);
      if (code != 0) return code;
      return a.riskFactorName.compareTo(b.riskFactorName);
    });
  }

  /// 打开高危因素多选选择器（首次打开懒加载本院字典；确定提交所选集合
  /// ——空集即清除该过滤条件；取消返回 null 不改动）。
  Future<void> _openFactorPicker() async {
    if (_factorsLoading) return;
    if (_factors == null) {
      setState(() {
        _factorsLoading = true;
        _factorsError = null;
      });
      try {
        final factors = await _highRiskFactorService.queryAll();
        if (!mounted) return;
        setState(() {
          _factors = _sortedFactors(factors);
          _factorsLoading = false;
        });
      } catch (e, st) {
        LogHelper.error('client:ChildAdvancedSearchDialog._openFactorPicker', e, st);
        if (!mounted) return;
        setState(() {
          _factorsError = _messageOf(e);
          _factorsLoading = false;
        });
      }
    }
    if (!mounted) return;
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _HighRiskFactorPickerDialog(
        factors: _factors ?? const [],
        loading: _factorsLoading,
        error: _factorsError,
        selected: Set.of(_selectedFactorIds),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selectedFactorIds = result);
  }

  /// 已选高危因素摘要（名称（编码）顿号连接；字典未加载完时按数量示意）。
  String get _selectedFactorSummary {
    if (_selectedFactorIds.isEmpty) return '';
    final names = (_factors ?? const <BaseHighRiskFactor>[]).where((f) => _selectedFactorIds.contains(f.id)).map((f) => '${f.riskFactorName}（${f.riskFactorCode}）').toList();
    return names.isNotEmpty ? names.join('、') : '已选 ${_selectedFactorIds.length} 项';
  }

  @override
  void initState() {
    super.initState();
    // Tab 0-查询条件 / Tab 1-查询结果；查询发起后自动切到结果 Tab。
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  /// IndexedStack 按 controller.index 手动切换，动画结束（index 落定）
  /// 时重建（同 child_create_page 惯例）。
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in _allControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 服务层异常转用户可读消息（同 child_create_view_model 口径）。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 文本条件取值（去空格，空返回 null 表示不参与查询）。
  String? _textOf(TextEditingController controller) {
    final v = controller.text.trim();
    return v.isEmpty ? null : v;
  }

  /// 数值条件取值（输入框已限纯数字，空返回 null）。
  int? _intOf(TextEditingController controller) => int.tryParse(controller.text.trim());

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(TextEditingController controller, String label) async {
    final initial = DateTime.tryParse(controller.text) ?? getIt<TimeService>().now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '选择$label',
    );
    if (picked == null) return;
    setState(() => controller.text = _formatDate(picked));
  }

  /// 执行组合查询（page 缺省回第一页）；区间起止倒挂时前置拦截，不发请求。
  Future<void> _runQuery({int page = 1}) async {
    final checkFrom = _textOf(_checkFromCtrl);
    final checkTo = _textOf(_checkToCtrl);
    final birthFrom = _textOf(_birthFromCtrl);
    final birthTo = _textOf(_birthToCtrl);
    final weekFrom = _intOf(_weekFromCtrl);
    final weekTo = _intOf(_weekToCtrl);
    final weightFrom = _intOf(_weightFromCtrl);
    final weightTo = _intOf(_weightToCtrl);
    String? rangeError;
    if (checkFrom != null && checkTo != null && checkFrom.compareTo(checkTo) > 0) {
      rangeError = '建档日期起始不能晚于截止日期';
    } else if (birthFrom != null && birthTo != null && birthFrom.compareTo(birthTo) > 0) {
      rangeError = '出生日期起始不能晚于截止日期';
    } else if (weekFrom != null && weekTo != null && weekFrom > weekTo) {
      rangeError = '出生孕周起始不能大于截止';
    } else if (weightFrom != null && weightTo != null && weightFrom > weightTo) {
      rangeError = '出生体重起始不能大于截止';
    }
    if (rangeError != null) {
      setState(() => _errorMsg = rangeError);
      return;
    }
    // 前置校验通过即切到结果 Tab（加载圈与结果/错误均在该 Tab 展示）。
    _tabController.animateTo(1);
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final (children, total) = await _childService.advancedQuery(
        checkTimeFrom: checkFrom,
        checkTimeTo: checkTo,
        birthDateFrom: birthFrom,
        birthDateTo: birthTo,
        name: _textOf(_nameCtrl),
        sex: _sex.isEmpty ? null : _sex,
        visitCardNo: _textOf(_cardCtrl),
        certificateNo: _textOf(_certCtrl),
        phone: _textOf(_phoneCtrl),
        guardianName: _textOf(_guardianCtrl),
        highRiskFactorIds: _selectedFactorIds.isEmpty ? null : _selectedFactorIds.toList(),
        gestationalWeekFrom: weekFrom,
        gestationalWeekTo: weekTo,
        birthWeightFrom: weightFrom,
        birthWeightTo: weightTo,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _children = children;
        _total = total;
        _page = page;
        _queried = true;
        _loading = false;
        _selected = null;
      });
    } catch (e, st) {
      LogHelper.error('client:ChildAdvancedSearchDialog._runQuery', e, st);
      if (!mounted) return;
      setState(() {
        _errorMsg = _messageOf(e);
        _children = const [];
        _total = 0;
        _queried = true;
        _loading = false;
        _selected = null;
      });
    }
  }

  /// 清空全部查询条件（保留当前查询结果，便于微调条件重新查询）。
  void _reset() {
    for (final controller in _allControllers) {
      controller.clear();
    }
    _sexFieldKey.currentState?.reset();
    setState(() {
      _sex = '';
      _selectedFactorIds = <String>{};
      _errorMsg = null;
    });
  }

  InputDecoration _decoration(ThemeData theme, String label) => InputDecoration(
    labelText: label,
    labelStyle: theme.textTheme.bodyMedium,
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.colorScheme.primary),
    ),
  );

  Widget _textField(ThemeData theme, TextEditingController controller, String label) => TextField(
    controller: controller,
    style: theme.textTheme.bodyMedium,
    decoration: _decoration(theme, label),
  );

  /// 只读日期框：点击弹日期选择器，回写 yyyy-MM-dd。
  Widget _dateField(ThemeData theme, TextEditingController controller, String label) => TextField(
    controller: controller,
    readOnly: true,
    style: theme.textTheme.bodyMedium,
    decoration: _decoration(theme, label).copyWith(
      suffixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
    ),
    onTap: () => _pickDate(controller, label),
  );

  /// 纯数字输入框（孕周/体重区间端点，SMALLINT 上限 32767 共 5 位）。
  Widget _numberField(ThemeData theme, TextEditingController controller, String label) => TextField(
    controller: controller,
    style: theme.textTheme.bodyMedium,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
    decoration: _decoration(theme, label),
  );

  Widget _sexField(ThemeData theme) => DropdownButtonFormField<String>(
    key: _sexFieldKey,
    initialValue: _sex,
    style: theme.textTheme.bodyMedium,
    decoration: _decoration(theme, '性别'),
    items: const [
      DropdownMenuItem<String>(value: '', child: Text('全部')),
      DropdownMenuItem<String>(value: '1', child: Text('男')),
      DropdownMenuItem<String>(value: '2', child: Text('女')),
    ],
    onChanged: (value) => setState(() => _sex = value ?? ''),
  );

  /// 高危因素多选字段：仿输入框（Material+InkWell），点击打开多选选择
  /// 器；已选时显示「名称（编码）」顿号连接摘要，未选时显示提示文案。
  Widget _buildHighRiskFactorField(ThemeData theme) {
    final hasSelection = _selectedFactorIds.isNotEmpty;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openFactorPicker,
        child: InputDecorator(
          decoration: _decoration(theme, '高危因素').copyWith(
            suffixIcon: _factorsLoading ? const SizedBox(width: 16, height: 16, child: Center(child: CircularProgressIndicator(strokeWidth: 2))) : Icon(Icons.expand_more, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ),
          child: Text(
            hasSelection ? _selectedFactorSummary : '请选择高危因素（可多选，留空不过滤）',
            style: theme.textTheme.bodyMedium?.copyWith(color: hasSelection ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.45)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// 两列条件行。
  Widget _pair(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      Expanded(child: right),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = _total <= 0 ? 0 : ((_total + _pageSize - 1) ~/ _pageSize);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GlassPanel(
          blur: 24,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, color: theme.colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        '高级搜索',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 双 Tab 布局：查询条件 / 查询结果，避免单页堆叠过密
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      const Tab(text: '查询条件'),
                      Tab(text: '查询结果（共 $_total 名）'),
                    ],
                  ),
                  const Divider(height: 1),
                  // IndexedStack 而非 TabBarView：两页常驻挂载，切 Tab
                  // 不丢条件输入与结果选中态；各 Tab 顶部留 8px 内距，
                  // 防首行浮动标签贴顶被裁
                  SizedBox(
                    height: 560,
                    child: IndexedStack(
                      index: _tabController.index,
                      children: [
                        // Tab 0：查询条件
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _pair(_dateField(theme, _checkFromCtrl, '建档日期起始'), _dateField(theme, _checkToCtrl, '建档日期截止')),
                                const SizedBox(height: 12),
                                _pair(_dateField(theme, _birthFromCtrl, '出生日期起始'), _dateField(theme, _birthToCtrl, '出生日期截止')),
                                const SizedBox(height: 12),
                                _pair(_textField(theme, _nameCtrl, '姓名'), _sexField(theme)),
                                const SizedBox(height: 12),
                                _pair(_textField(theme, _cardCtrl, '就诊卡号'), _textField(theme, _certCtrl, '证件号码')),
                                const SizedBox(height: 12),
                                _pair(_textField(theme, _phoneCtrl, '联系电话'), _textField(theme, _guardianCtrl, '监护人姓名')),
                                const SizedBox(height: 12),
                                _pair(_numberField(theme, _weekFromCtrl, '出生孕周起始（周）'), _numberField(theme, _weekToCtrl, '出生孕周截止（周）')),
                                const SizedBox(height: 12),
                                _pair(_numberField(theme, _weightFromCtrl, '出生体重起始（g）'), _numberField(theme, _weightToCtrl, '出生体重截止（g）')),
                                const SizedBox(height: 12),
                                _buildHighRiskFactorField(theme),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _reset,
                                      icon: const Icon(Icons.refresh_outlined, size: 16),
                                      label: const Text('重置'),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _loading ? null : () => _runQuery(),
                                      icon: const Icon(Icons.search_outlined, size: 16),
                                      label: const Text('查询'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '文本条件均为精确匹配；不填任何条件则按建档时间倒序分页浏览全院档案',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                ),
                                if (_errorMsg != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _errorMsg!,
                                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // Tab 1：查询结果
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text('查询结果（共 $_total 名）', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  if (_loading)
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(child: _buildResults(theme)),
                              const SizedBox(height: 8),
                              _buildPager(theme, totalPages),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('关闭'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
                        child: const Text('确定'),
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
  }

  /// 结果列表：加载中 / 未查询 / 无数据空态 / 数据行。
  Widget _buildResults(ThemeData theme) {
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
        ),
      );
    }
    if (!_queried) {
      return Center(
        child: Text(
          '请设置查询条件后点击「查询」',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      );
    }
    if (_children.isEmpty) {
      return Center(
        child: Text(
          '暂无符合条件的数据',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.separated(
      itemCount: _children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _resultRow(theme, _children[index]),
    );
  }

  /// 结果行：姓名/性别/出生日期 + 联系电话/居住地址 + 建档日期；单击选中
  /// 高亮，双击直接选定返回。
  Widget _resultRow(ThemeData theme, ChildInfo c) {
    final sex = switch (c.sex) {
      '1' => '男',
      '2' => '女',
      _ => '',
    };
    final address = [
      c.addressProvince,
      c.addressCity,
      c.addressCounty,
      c.addressTown,
      c.addressVillage,
      c.addressDetails,
    ].whereType<String>().where((s) => s.isNotEmpty).join();
    final selected = _selected?.id == c.id;
    return GlassPanel(
      blur: 12,
      borderRadius: 12,
      color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45) : null,
      borderColor: selected ? theme.colorScheme.primary.withValues(alpha: 0.6) : null,
      child: GestureDetector(
        // ListTile 无 onDoubleTap 参数，双击由外层 GestureDetector 识别
        //（与内部 InkWell 的单击手势共处同一竞技场，单击约延迟一个双击
        // 判定窗口，换取双击直接选定）。
        onDoubleTap: () => Navigator.of(context).pop(c),
        child: ListTile(
          dense: true,
          onTap: () => setState(() => _selected = c),
          title: Text(
            '${c.name}${sex.isEmpty ? '' : '  $sex'}  ${c.birthDate}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            [
              if (c.phone != null && c.phone!.isNotEmpty) '电话 ${c.phone!}',
              if (address.isNotEmpty) address,
            ].join(' · '),
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_circle_outline, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Text('建档 ${c.checkTime}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  /// 分页条：总数与页码 + 首页/上一页/下一页/末页（越界禁用）。
  Widget _buildPager(ThemeData theme, int totalPages) {
    return Row(
      children: [
        Text(
          _total > 0 ? '共 $_total 名 · 第 $_page/$totalPages 页' : '共 0 名',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        TextButton(
          onPressed: _page > 1 && !_loading ? () => _runQuery(page: 1) : null,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('首页'),
        ),
        TextButton(
          onPressed: _page > 1 && !_loading ? () => _runQuery(page: _page - 1) : null,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('上一页'),
        ),
        TextButton(
          onPressed: _page < totalPages && !_loading ? () => _runQuery(page: _page + 1) : null,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('下一页'),
        ),
        TextButton(
          onPressed: _page < totalPages && !_loading ? () => _runQuery(page: totalPages) : null,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('末页'),
        ),
      ],
    );
  }
}

/// 高危因素多选选择器（毛玻璃对话框，仿用户表单科室多选）：CheckboxListTile
/// 逐项勾选（五色圆点 + 名称（编码）），支持全选/清空；「确定」提交所选
/// 集合——**空集允许确定**（语义为清除高危因素过滤条件），「取消」返回
/// null 不改动当前选择。
class _HighRiskFactorPickerDialog extends StatefulWidget {
  const _HighRiskFactorPickerDialog({required this.factors, required this.loading, required this.error, required this.selected});

  /// 本院高危因素字典（已排序）。
  final List<BaseHighRiskFactor> factors;

  /// 字典加载中。
  final bool loading;

  /// 字典加载失败信息（非 null 时列表区显示错误态）。
  final String? error;

  /// 当前已选 ID 集合。
  final Set<String> selected;

  @override
  State<_HighRiskFactorPickerDialog> createState() => _HighRiskFactorPickerDialogState();
}

class _HighRiskFactorPickerDialogState extends State<_HighRiskFactorPickerDialog> {
  late final Set<String> _selected = Set.of(widget.selected);

  void _toggle(String id, bool checked) {
    setState(() {
      checked ? _selected.add(id) : _selected.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = widget.factors.isNotEmpty && _selected.length == widget.factors.length;
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
                    Icon(Icons.medical_services_outlined, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '选择高危因素（可多选）',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '查询保存过所选因素中任意一个的儿童；不选即不过滤',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: widget.loading
                      ? const Center(child: CircularProgressIndicator())
                      : widget.error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '高危因素字典加载失败：${widget.error}',
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text('请关闭后重新打开选择器重试', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                            ],
                          ),
                        )
                      : widget.factors.isEmpty
                      ? Center(
                          child: Text('本院尚未配置高危因素', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: widget.factors.length,
                          itemBuilder: (context, index) {
                            final factor = widget.factors[index];
                            return CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              value: _selected.contains(factor.id),
                              onChanged: (checked) => _toggle(factor.id, checked ?? false),
                              title: Row(
                                children: [
                                  // 五色色标（同互斥规则/高危因素管理口径）
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: RiskColorPalette.colorOf(factor.riskColor, theme), shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${factor.riskFactorName}（${factor.riskFactorCode}）',
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.factors.isEmpty || allSelected
                          ? null
                          : () => setState(
                              () => _selected
                                ..clear()
                                ..addAll(widget.factors.map((f) => f.id)),
                            ),
                      child: const Text('全选'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _selected.isEmpty ? null : () => setState(_selected.clear),
                      child: const Text('清空'),
                    ),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                    const SizedBox(width: 12),
                    FilledButton(
                      // 空选允许确定：语义为清除高危因素过滤条件
                      onPressed: () => Navigator.of(context).pop(Set.of(_selected)),
                      child: const Text('确 定'),
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
