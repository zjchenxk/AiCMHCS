import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/child/child_create_view_model.dart';
import 'package:client/views/child/child_form_widgets.dart';
import 'package:client/widgets/high_risk_factor_quick_add_dialog.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 儿童「高危因素」Tab 面板：按高危因素字典的高危颜色（绿色/黄色/橙色/
/// 红色/紫色）分五色卡片，卡片内按「大类→小类→名称」树形展示高危因素
/// （按编码+名称排序），每个高危因素带复选框勾选（随整单保存）。
///
/// 互斥规则：勾选绿色卡片的【无母亲及胎儿、新生儿的高危因素】后，其余
/// 四色卡片复选框禁用并清空勾选；勾选其余四色任一项则绿色该项取消勾选
/// 并禁用（其余绿色项不受影响）。
/// 顶部提供模糊搜索（计数【当前/总数】+【下一个】循环定位）与【新增
/// 高危因素】快速入口（默认编码按颜色映射、允许重复，不走唯一性校验）。
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
    super.dispose();
  }

  /// 搜索关键词变化：重算命中队列（视觉顺序）并定位第一项。
  void _onSearchChanged(String query) {
    final matches = _matchIdsInVisualOrder(query);
    _matchIds
      ..clear()
      ..addAll(matches);
    _matchIndex = 0;
    if (_matchIds.isNotEmpty) {
      _jumpToMatchAt(0);
    }
    setState(() {});
  }

  /// 按视觉顺序（五色卡片序 → 卡片内编码+名称序）收集命中项 id。
  List<String> _matchIdsInVisualOrder(String query) {
    final q = query.toLowerCase();
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
      orElse: () => const BaseHighRiskFactor(id: '', riskFactorCode: '', riskFactorName: '', creatorId: '', creatorName: '', hospId: '', hospName: ''),
    );
    // 祖先节点展开后子项才可见
    if (factor.riskFactorCategory?.isNotEmpty ?? false) {
      _collapsedKeys.remove('cat:${factor.riskColor}|${factor.riskFactorCategory}');
    }
    if ((factor.riskFactorSubcategory?.isNotEmpty ?? false) && (factor.riskFactorCategory?.isNotEmpty ?? false)) {
      _collapsedKeys.remove('sub:${factor.riskColor}|${factor.riskFactorCategory}|${factor.riskFactorSubcategory}');
    }
    final rowContext = _rowKeys[id]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(rowContext, duration: const Duration(milliseconds: 300), alignment: 0.15);
    }
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
          const SizedBox(height: 16),
          for (final colorName in RiskColorPalette.names) _buildColorCard(theme, vm, colorName, editable),
          if (editable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '勾选的高危因素随【保存】一并入库；绿色【无高危因素】与其余四色互斥',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 五色卡片：卡片头（色点 + 颜色名 + 勾选数）+ 树形高危因素列表。
  Widget _buildColorCard(ThemeData theme, ChildCreateViewModel vm, String colorName, bool editable) {
    final factors = _factorsOfColor(colorName);
    final checkedCount = factors.where((f) => vm.checkedHighRiskIds.contains(f.id)).length;
    return Container(
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
                Text(
                  '$colorName高危因素',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
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
                '暂无$colorName高危因素',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            )
          else
            ..._buildTreeRows(theme, vm, colorName, factors, editable),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 色内树形行：大类 → 小类 → 高危因素叶子（可空层级自动上提）。
  List<Widget> _buildTreeRows(ThemeData theme, ChildCreateViewModel vm, String colorName, List<BaseHighRiskFactor> factors, bool editable) {
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
        rows.add(_treeHeader(theme, catKey, category, editable, catFactors.length, Icons.folder_outlined, depth: 0));
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
          rows.add(_treeHeader(theme, subKey, subcategory, editable, subBuckets[subcategory]!.length, Icons.subdirectory_arrow_right_outlined, depth: 1));
          if (!expanded) continue;
        }
        for (final f in (hasCategory && !hasSub ? subBuckets[null] ?? const [] : subBuckets[subcategory] ?? const [])) {
          rows.add(_factorRow(theme, vm, f, editable, hasCategory ? 1 : 0, hasSub && hasCategory ? 1 : 0));
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
            Icon(expanded ? Icons.folder_open_outlined : Icons.folder_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
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

  /// 高危因素叶子行：复选框 + 名称（尾缀编码）；互斥时灰化禁用
  /// （勾选绿色「无高危因素」后其余四色禁用，反之绿色该项禁用）。
  Widget _factorRow(ThemeData theme, ChildCreateViewModel vm, BaseHighRiskFactor factor, bool editable, int depth1, int depth2) {
    final checked = vm.checkedHighRiskIds.contains(factor.id);
    final canToggle = vm.canToggleHighRisk(factor, editable: editable);
    return Container(
      key: _rowKeys.putIfAbsent(factor.id, () => GlobalKey()),
      padding: EdgeInsets.only(left: 12.0 + depth1 * 18.0 + depth2 * 18.0),
      child: CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.only(right: 8),
        value: checked,
        onChanged: canToggle ? (v) => vm.toggleHighRiskFactor(factor, v ?? false) : null,
        title: Text(
          '${factor.riskFactorName}（${factor.riskFactorCode}）',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }

  /// 快速新增高危因素对话框（确定后自动勾选新增项）。
  Future<void> _showQuickAddDialog() async {
    final created = await HighRiskFactorQuickAddDialog.show(context);
    if (created != null && mounted) {
      widget.viewModel.addCreatedFactor(created);
    }
  }
}
