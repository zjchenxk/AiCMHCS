import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/high_risk_factor_quick_add_dialog.dart';
import 'package:client/widgets/high_risk_factor_remark_dialog.dart';
import 'package:common/model.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童「高危因素」Tab 面板：按高危因素字典的高危颜色（绿色/黄色/橙色/
/// 红色/紫色）分五色卡片，卡片内按「大类→小类→名称」树形展示高危因素
/// （按编码+名称排序），每个高危因素带复选框勾选（随整单保存）。
///
/// 互斥规则：勾选绿色【无母亲及胎儿、新生儿的高危因素】时自动清除其余
/// 四色勾选（该标记项不落库）；勾选其余四色任一项时自动取消该标记项。
/// 顶部工具栏（搜索 / 计数 / 下一个 / 五色快速导航 / 新增）固定不随
/// 列表滚动；搜索命中项高亮并可循环定位，清空搜索词恢复。
/// 黄/橙/红/紫卡片每项末尾提供【...】菜单（备注编辑），备注显示在名称
/// 后的括号内并随档案保存。
class ChildHighRiskFactorPanel extends StatefulWidget {
  const ChildHighRiskFactorPanel({super.key, required this.viewModel, required this.editable});

  final ChildCreateViewModel viewModel;

  /// 是否可编辑（新增/修改录入态）；浏览态复选框禁用、仅回显勾选。
  final bool editable;

  @override
  State<ChildHighRiskFactorPanel> createState() => _ChildHighRiskFactorPanelState();
}

class _ChildHighRiskFactorPanelState extends State<ChildHighRiskFactorPanel> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索命中项的 factor id 队列（按视觉顺序）与当前定位序号（0 基）。
  final List<String> _matchIds = [];
  int _matchIndex = 0;

  /// 被手动折叠的树节点键集合（cat:/sub: 前缀）。反向记录——未列入
  /// 即视为展开，保证 5 个卡片的大类/小类默认全部展开，字典新增节点
  /// 也自动展开。
  final Set<String> _collapsedKeys = {};

  /// 叶子行滚动定位键（factor id → GlobalKey）。
  final Map<String, GlobalKey> _rowKeys = {};

  /// 五色卡片滚动定位键（colorName → GlobalKey，快速导航用）。
  final Map<String, GlobalKey> _cardKeys = {};

  /// 卡片列表滚动控制器（快速导航精确滚动用）。
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // 字典/勾选集合由页面 _init 统一加载（loadHighRiskData）；此处仅在
    // 数据缺席时兜底拉取
    if (widget.viewModel.highRiskDict.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.viewModel.loadHighRiskData());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 搜索关键词变化：重算命中队列（视觉顺序），重建后定位第一项；
  /// 清空关键词时清除计数与高亮。
  void _onSearchChanged(String query) {
    final matches = _matchIdsInVisualOrder(query);
    _matchIds
      ..clear()
      ..addAll(matches);
    _matchIndex = 0;
    setState(() {});
    if (_matchIds.isNotEmpty) {
      // 等本次重建完成后行 key 才可定位（否则 currentContext 为旧树）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToMatchAt(0);
      });
    }
  }

  /// 按视觉顺序（五色卡片序 → 卡片内编码+名称序）收集命中项 id。
  List<String> _matchIdsInVisualOrder(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final matches = <String>[];
    for (final colorName in RiskColorPalette.names) {
      for (final factor in _factorsOfColor(colorName)) {
        if (factor.riskFactorName.toLowerCase().contains(q)) {
          matches.add(factor.id);
        }
      }
    }
    return matches;
  }

  /// 【下一个】：循环定位下一个命中项。
  void _nextMatch() {
    if (_matchIds.isEmpty) return;
    final next = (_matchIndex + 1) % _matchIds.length;
    _jumpToMatchAt(next);
  }

  /// 定位命中项：确保祖先树节点展开后滚动至可见，并更新当前序号。
  void _jumpToMatchAt(int index) {
    setState(() => _matchIndex = index);
    if (_matchIds.isEmpty) return;
    final id = _matchIds[index];
    final factor = widget.viewModel.highRiskDict.firstWhere(
      (f) => f.id == id,
      orElse: () => const BaseHighRiskFactor(
        id: '',
        riskFactorCode: '',
        riskFactorName: '',
        creatorId: '',
        creatorName: '',
        hospId: '',
        hospName: '',
      ),
    );
    // 祖先节点展开后子项才可见
    if (factor.riskFactorCategory?.isNotEmpty ?? false) {
      _collapsedKeys.remove('cat:${factor.riskColor}|${factor.riskFactorCategory}');
    }
    if ((factor.riskFactorSubcategory?.isNotEmpty ?? false) && (factor.riskFactorCategory?.isNotEmpty ?? false)) {
      _collapsedKeys.remove('sub:${factor.riskColor}|${factor.riskFactorCategory}|${factor.riskFactorSubcategory}');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[id]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(rowContext, duration: const Duration(milliseconds: 300), alignment: 0.15);
      }
    });
  }

  /// 快速导航：把指定颜色卡片精确滚动到视口顶部（末尾卡片受最大滚动
  /// 距离限制时滚到底）。
  ///
  /// 不用 `Scrollable.ensureVisible`：它对「目标已完全可见」场合不产生
  /// 滚动、且 alignment 为比例值，会产生偏移；这里直接用
  /// [RenderAbstractViewport.getOffsetToReveal] 求出目标顶部的精确偏移，
  /// 再夹到合法滚动范围后动画滚动。
  void _scrollToCard(String colorName) {
    final cardContext = _cardKeys[colorName]?.currentContext;
    if (cardContext == null || !_scrollCtrl.hasClients) return;
    final box = cardContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final viewport = RenderAbstractViewport.of(box);
    final target = viewport.getOffsetToReveal(box, 0.0).offset;
    final position = _scrollCtrl.position;
    _scrollCtrl.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 某颜色的全部高危因素（按编码+名称排序）。
  List<BaseHighRiskFactor> _factorsOfColor(String colorName) {
    final factors = widget.viewModel.highRiskDict.where((f) => f.riskColor == colorName).toList()
      ..sort((a, b) {
        final byCode = a.riskFactorCode.compareTo(b.riskFactorCode);
        if (byCode != 0) return byCode;
        return a.riskFactorName.compareTo(b.riskFactorName);
      });
    return factors;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<ChildCreateViewModel>();
    final editable = widget.editable;
    final query = _searchCtrl.text.trim();
    final noMatch = query.isNotEmpty && _matchIds.isEmpty;

    // 工具栏固定在滚动区域外；仅卡片列表参与滚动
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：五色快速导航 + 搜索 + 计数/下一个 + 新增
              Row(
                children: [
                  for (final colorName in RiskColorPalette.names) ...[
                    _buildNavChip(theme, vm, colorName),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: theme.textTheme.bodyMedium,
                      decoration: childGlassDecoration(theme, '输入字符模糊搜索高危因素名称'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (query.isNotEmpty) ...[
                    Text(
                      noMatch ? '无匹配记录' : '${_matchIndex + 1}/${_matchIds.length}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: noMatch ? theme.colorScheme.error : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _matchIds.isEmpty ? null : _nextMatch,
                      child: const Text('下一个'),
                    ),
                  ],
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: editable ? _showQuickAddDialog : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增高危因素'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 卡片列表滚动区
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                for (final colorName in RiskColorPalette.names) _buildColorCard(theme, vm, colorName, editable, query),
                if (editable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '勾选的高危因素随【保存】一并入库；绿色【无高危因素】与其余四色互斥且不入库',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 五色快速导航按钮：尺寸/字号与右侧【新增高危因素】按钮一致
  /// （同为 Material 按钮、默认密度与按钮主题字号），色点作前导图标。
  Widget _buildNavChip(ThemeData theme, ChildCreateViewModel vm, String colorName) {
    final color = RiskColorPalette.colorOf(colorName, theme);
    // 黄/橙/红/紫显示该色已勾选项目数（便于回看选中项）；绿色为「无高危
    // 因素」等标记项，不显示计数；计数为 0 时同样不显示（仅展示有选中
    // 项的颜色，突出需要回看的目标）
    final checked = vm.checkedHighRiskCountOfColor(colorName);
    final showCount = colorName != '绿色' && checked > 0;
    return Tooltip(
      message: showCount ? '滚动到$colorName卡片（已选 $checked 项）' : '滚动到$colorName卡片',
      child: OutlinedButton.icon(
        onPressed: () => _scrollToCard(colorName),
        icon: Icon(Icons.circle, size: 10, color: color),
        label: Text(showCount ? '$colorName（$checked）' : colorName),
      ),
    );
  }

  /// 五色卡片：卡片头（色点 + 颜色名 + 勾选数）+ 树形高危因素列表。
  Widget _buildColorCard(ThemeData theme, ChildCreateViewModel vm, String colorName, bool editable, String query) {
    final factors = _factorsOfColor(colorName);
    final checkedCount = factors.where((f) => vm.checkedHighRiskIds.contains(f.id)).length;
    return Container(
      key: _cardKeys.putIfAbsent(colorName, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: RiskColorPalette.backgroundOf(colorName, theme),
        border: Border.all(color: RiskColorPalette.borderOf(colorName, theme)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: RiskColorPalette.colorOf(colorName, theme), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(colorName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(
                  '$checkedCount 项',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          if (factors.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                '暂无$colorName项目',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            )
          else
            ..._buildTreeRows(theme, vm, colorName, factors, editable, query),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 色内树形行：大类 → 小类 → 高危因素叶子（可空层级自动上提）。
  List<Widget> _buildTreeRows(ThemeData theme, ChildCreateViewModel vm, String colorName, List<BaseHighRiskFactor> factors, bool editable, String query) {
    // 大类 → 小类 → 叶子 分桶
    final categories = <String?, List<BaseHighRiskFactor>>{};
    for (final f in factors) {
      categories.putIfAbsent(f.riskFactorCategory, () => []).add(f);
    }
    final rows = <Widget>[];
    // 大类排序：空（无大类）放最后，其余按名称
    final catKeys = categories.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });
    for (final category in catKeys) {
      final catFactors = categories[category]!;
      final hasCategory = category != null;
      if (hasCategory) {
        final catKey = 'cat:$colorName|$category';
        final expanded = !_collapsedKeys.contains(catKey);
        rows.add(_treeHeader(theme, catKey, category, editable, catFactors.length, Icons.folder, depth: 0));
        if (!expanded) continue;
      }
      // 大类下再按小类分桶（小类可空）
      final subBuckets = <String?, List<BaseHighRiskFactor>>{};
      for (final f in catFactors) {
        subBuckets.putIfAbsent(f.riskFactorSubcategory, () => []).add(f);
      }
      final subKeys = subBuckets.keys.toList()
        ..sort((a, b) {
          if (a == null) return 1;
          if (b == null) return -1;
          return a.compareTo(b);
        });
      for (final subcategory in subKeys) {
        final hasSub = subcategory != null;
        if (hasCategory && hasSub) {
          final subKey = 'sub:$colorName|$category|$subcategory';
          final expanded = !_collapsedKeys.contains(subKey);
          rows.add(
            _treeHeader(theme, subKey, subcategory, editable, subBuckets[subcategory]!.length, Icons.subdirectory_arrow_right_outlined, depth: 1),
          );
          if (!expanded) continue;
        }
        for (final f in (hasCategory && !hasSub ? subBuckets[null] ?? const [] : subBuckets[subcategory] ?? const [])) {
          rows.add(_factorRow(theme, vm, f, editable, hasCategory ? 1 : 0, hasSub && hasCategory ? 1 : 0, query));
        }
      }
    }
    return rows;
  }

  /// 树节点标题行（大类/小类）：按层级缩进（与叶子同基准 12px、每级
  /// 18px），呈现「大类 → 小类 → 高危因素」树形层级。
  Widget _treeHeader(ThemeData theme, String key, String name, bool editable, int count, IconData icon, {required int depth}) {
    final expanded = !_collapsedKeys.contains(key);
    return InkWell(
      onTap: () => setState(() => expanded ? _collapsedKeys.add(key) : _collapsedKeys.remove(key)),
      child: Padding(
        padding: EdgeInsets.only(left: 12.0 + depth * 18.0, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(expanded ? Icons.indeterminate_check_box_outlined : Icons.add_box_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: depth == 0 ? FontWeight.bold : null)),
            ),
            Text('$count 项', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// 高危因素叶子行：复选框 + 名称（备注括号展示）+【...】备注菜单
  /// （仅黄/橙/红/紫；绿色为「无高危因素」等标记项，无备注）。
  Widget _factorRow(ThemeData theme, ChildCreateViewModel vm, BaseHighRiskFactor factor, bool editable, int depth1, int depth2, String query) {
    final checked = vm.checkedHighRiskIds.contains(factor.id);
    final canToggle = vm.canToggleHighRisk(factor, editable: editable);
    final matched = query.isNotEmpty && factor.riskFactorName.toLowerCase().contains(query.toLowerCase());
    final remark = vm.highRiskRemarkOf(factor.id);
    final showRemarkMenu = factor.riskColor != null && factor.riskColor != '绿色';

    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: matched ? FontWeight.bold : null,
      color: matched ? theme.colorScheme.primary : null,
    );

    return Container(
      key: _rowKeys.putIfAbsent(factor.id, () => GlobalKey()),
      padding: EdgeInsets.only(left: 12.0 + depth1 * 18.0 + depth2 * 18.0),
      decoration: BoxDecoration(
        // 搜索命中项高亮（跟随主题色，透明底，不硬编码颜色）
        color: matched ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(right: 4),
              value: checked,
              onChanged: canToggle ? (v) => vm.toggleHighRiskFactor(factor, v ?? false) : null,
              title: Text.rich(
                TextSpan(
                  text: factor.riskFactorName,
                  style: titleStyle,
                  children: [
                    if (remark.isNotEmpty)
                      TextSpan(
                        text: '（$remark）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.normal,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (showRemarkMenu)
            IconButton(
              // 仅该高危因素被选中（且处于录入态）时可用；未选中灰化禁用。
              // 点击直接弹出备注编辑对话框（无中间菜单）。
              onPressed: (checked && editable) ? () => _editRemark(factor) : null,
              tooltip: (checked && editable) ? '备注' : '勾选后可编辑备注',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.more_horiz,
                size: 18,
                color: (checked && editable) ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// 备注编辑：弹出对话框（回填已有备注），确定后写入 VM 并刷新列表展示。
  Future<void> _editRemark(BaseHighRiskFactor factor) async {
    final remark = await HighRiskFactorRemarkDialog.show(
      context,
      factorName: factor.riskFactorName,
      initialRemark: widget.viewModel.highRiskRemarkOf(factor.id),
    );
    if (remark != null && mounted) {
      widget.viewModel.setHighRiskRemark(factor.id, remark);
    }
  }

  /// 快速新增高危因素对话框（确定后自动勾选新增项）。
  Future<void> _showQuickAddDialog() async {
    final created = await HighRiskFactorQuickAddDialog.show(context);
    if (created != null && mounted) {
      widget.viewModel.addCreatedFactor(created);
    }
  }
}
