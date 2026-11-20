import 'package:client/utils/risk_color.dart';
import 'package:client/view_models/system/high_risk_factor_exclusion_management_view_model.dart';
import 'package:client/views/base/base_page.dart';
import 'package:client/views/system/high_risk_factor_exclusion_info_form.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 高危因素互斥规则管理页：左侧为互斥规则列表（每行以「A × B（× C）」
/// 展示互斥的高危因素，色标沿用高危因素五色），右侧为新增/修改编辑区
/// （三个高危因素下拉，前两项必填、第三项可选）。增删改按钮按操作权限
/// 9910000001/9910000002/9910000003 控制。
class HighRiskFactorExclusionManagementPage extends BasePage {
  const HighRiskFactorExclusionManagementPage({
    super.key,
    required super.loginUser,
    required super.child,
  });

  @override
  State<HighRiskFactorExclusionManagementPage> createState() => _HighRiskFactorExclusionManagementPageState();
}

class _HighRiskFactorExclusionManagementPageState extends State<HighRiskFactorExclusionManagementPage> {
  /// dispose 中不能再用 context 取 Provider，保存实例引用供移除监听
  late final HighRiskFactorExclusionManagementViewModel _viewModel;

  @override
  void initState() {
    super.initState();

    // 通过 Provider 获取全局注入的实例（不再自己 new）
    _viewModel = context.read<HighRiskFactorExclusionManagementViewModel>();
    // 每次进入页面强制重拉（保证切回本页时数据一致）；
    // 延迟到首帧后发起，避免 build 期间同步 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _viewModel.loadData();
      }
    });

    // 监听 errorMsg 变化，用 SnackBar 提示错误
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    // 注意：实例来自 Provider 全局注入，这里只移除监听，不要 viewModel.dispose()
    _viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;

    //获取当前主题
    final ThemeData theme = Theme.of(context);

    if (_viewModel.errorMsg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.errorMsg!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onError,
            ),
          ),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating, // 悬浮式，不遮挡底部布局
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

  @override
  Widget build(BuildContext context) {
    // 使用 watch 监听变化，VM notifyListeners 后自动刷新
    final viewModel = context.watch<HighRiskFactorExclusionManagementViewModel>();

    return viewModel.loading ? const Center(child: CircularProgressIndicator()) : _buildBody(context, viewModel);
  }

  Widget _buildBody(BuildContext context, HighRiskFactorExclusionManagementViewModel viewModel) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧：互斥规则列表
        Expanded(
          flex: 4,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: '高危因素互斥规则',
                  icon: Icons.block_outlined,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 新增按钮按「新增互斥规则」操作权限灰化
                      IconButton(
                        tooltip: viewModel.canCreate ? '新增互斥规则' : '无新增操作权限',
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: viewModel.loading || viewModel.busy || !viewModel.canCreate ? null : viewModel.startCreate,
                      ),
                      IconButton(
                        tooltip: '刷新',
                        icon: const Icon(Icons.refresh_outlined, size: 20),
                        // 手动整表重拉（进入页面时 loadData 已自动重拉）
                        onPressed: viewModel.loading || viewModel.busy ? null : viewModel.loadData,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: viewModel.isEmpty
                      ? const Center(child: Text('暂无互斥规则，请新增'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: viewModel.exclusions.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            indent: 12,
                            endIndent: 12,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          itemBuilder: (context, index) => _buildRuleTile(context, viewModel, viewModel.exclusions[index]),
                        ),
                ),
              ],
            ),
          ),
        ),

        // 右侧：互斥规则信息表单（按表单模式切换内容）
        Expanded(
          flex: 6,
          child: Card(
            color: theme.colorScheme.surfaceContainer,
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  theme: theme,
                  title: viewModel.formMode == HighRiskFactorExclusionFormMode.create ? '新增互斥规则' : '互斥规则信息',
                  icon: Icons.info_outlined,
                ),
                Expanded(
                  child: switch (viewModel.formMode) {
                    HighRiskFactorExclusionFormMode.empty => const Center(child: Text('请先在左侧选择互斥规则')),
                    // key 含模式与规则 ID：切换模式/选中项时表单重建，
                    // 实现新增表单清空、编辑表单回填
                    _ => HighRiskFactorExclusionInfoForm(
                      key: ValueKey(
                        viewModel.formMode == HighRiskFactorExclusionFormMode.create ? 'create' : 'edit:${viewModel.selected!.id}',
                      ),
                      viewModel: viewModel,
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 面板抬头：primaryContainer 背景条（左右两栏同款）。
  Widget _buildPanelHeader({
    required ThemeData theme,
    required String title,
    required IconData icon,
    Widget? trailing,
  }) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// 单条互斥规则：色标高危因素胶囊以「×」相连，附创建人与创建时间。
  Widget _buildRuleTile(
    BuildContext context,
    HighRiskFactorExclusionManagementViewModel viewModel,
    BaseHighRiskFactorExclusion rule,
  ) {
    final theme = Theme.of(context);
    final selected = viewModel.formMode != HighRiskFactorExclusionFormMode.create && viewModel.selected?.id == rule.id;
    final ids = rule.riskFactorIds;
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => viewModel.selectExclusion(rule),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: 16,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var i = 0; i < ids.length; i++) ...[
                          if (i > 0)
                            Icon(
                              Icons.close,
                              size: 12,
                              color: theme.colorScheme.error.withValues(alpha: 0.8),
                            ),
                          _buildFactorChip(theme, viewModel, ids[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  '创建人：${rule.creatorName}${(rule.createTime ?? '').isEmpty ? '' : ' · ${rule.createTime}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 高危因素胶囊：高危颜色浅色底 + 色标圆点 + 名称（编码）。
  Widget _buildFactorChip(
    ThemeData theme,
    HighRiskFactorExclusionManagementViewModel viewModel,
    String factorId,
  ) {
    final color = viewModel.factorColorOf(factorId);
    final name = viewModel.factorNameOf(factorId);
    final code = viewModel.factorCodeOf(factorId);
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: RiskColorPalette.backgroundOf(color, theme),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: RiskColorPalette.borderOf(color, theme),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: RiskColorPalette.colorOf(color, theme),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              code.isEmpty ? name : '$name（$code）',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
