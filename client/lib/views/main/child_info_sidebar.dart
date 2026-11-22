import 'dart:convert';

import 'package:client/models/child_sidebar.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 主界面右侧儿童信息侧边栏。
///
/// 展示当前儿童（MainViewModel.child）的头像、基本信息、五色高危分级、
/// 高危因素列表与历次检查时间轴：未选定儿童时整体隐藏；展开宽度 280，
/// 收起后为 48 宽的竖条，内容区独立上下滚动。扩展信息/头像由
/// MainViewModel 随当前儿童变化异步加载，加载失败时保留基础信息与
/// 演示数据（见 models/child_sidebar.dart）。
class ChildInfoSidebar extends StatefulWidget {
  /// 构造函数。
  const ChildInfoSidebar({super.key});

  /// 展开宽度（需求范围 250-300）。
  static const double expandedWidth = 280;

  /// 收起宽度（仅保留展开按钮与头像）。
  static const double collapsedWidth = 48;

  @override
  State<ChildInfoSidebar> createState() => _ChildInfoSidebarState();
}

class _ChildInfoSidebarState extends State<ChildInfoSidebar> {
  /// 展开态内容区滚动控制器：显式同挂 Scrollbar 与 SingleChildScrollView——
  /// Web 桌面平台下 SingleChildScrollView 缺省不关联 PrimaryScrollController，
  /// 无控制器的 Scrollbar 在滚动条淡出动画时会断言失败（整屏红闪 + 报错
  /// 日志「The Scrollbar's ScrollController has no ScrollPosition attached」）。
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MainViewModel>(
      builder: (context, mainViewModel, _) {
        final data = mainViewModel.childSidebarData;
        // 未选择当前儿童时不占位，保持主界面原布局
        if (mainViewModel.child.id.isEmpty || data == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
          width: mainViewModel.childSidebarCollapsed ? ChildInfoSidebar.collapsedWidth : ChildInfoSidebar.expandedWidth,
          child: GlassPanel(
            borderRadius: 16,
            child: mainViewModel.childSidebarCollapsed
                ? _buildCollapsedRail(theme, mainViewModel, data)
                // 固定内容宽度：收起动画期间内容被面板裁切，不因宽度收缩
                // 触发文字换行/溢出报错（与左侧功能菜单同一处理）
                : OverflowBox(
                    alignment: AlignmentDirectional.topStart,
                    minWidth: ChildInfoSidebar.expandedWidth - 1,
                    maxWidth: ChildInfoSidebar.expandedWidth - 1,
                    child: SizedBox(
                      width: ChildInfoSidebar.expandedWidth - 1,
                      child: _buildExpandedPanel(theme, mainViewModel, data),
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// 收起态：展开按钮 + 头像 + 竖向「当前儿童」文字。
  Widget _buildCollapsedRail(ThemeData theme, MainViewModel mainViewModel, ChildSidebarData data) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Tooltip(
          message: '展开儿童信息',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            highlightColor: theme.colorScheme.primary.withValues(alpha: 0.16),
            onTap: mainViewModel.toggleChildSidebar,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.keyboard_double_arrow_left,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundImage: _decodeAvatar(data.avatarBase64),
          child: Icon(Icons.child_care_outlined, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // 竖排「当前儿童」后追加儿童姓名（主题色加粗便于辨识）；
              // 姓名较长超出栏高时允许上下滚动，短时保持垂直居中
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final char in '当前儿童'.characters)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              char,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        if (data.name.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final char in data.name.trim().characters)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                char,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 展开态：固定标题栏 + 独立滚动内容区。
  Widget _buildExpandedPanel(ThemeData theme, MainViewModel mainViewModel, ChildSidebarData data) {
    return Column(
      children: [
        _buildHeader(theme, mainViewModel),
        // 扩展档案/头像加载中的细进度条（不遮挡已展示的基础信息）
        if (mainViewModel.childSidebarLoading)
          LinearProgressIndicator(
            minHeight: 2,
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfile(theme, data),
                  const SizedBox(height: 18),
                  _buildRiskScale(theme, data),
                  const SizedBox(height: 18),
                  _buildBasicMetrics(theme, data),
                  const SizedBox(height: 18),
                  _buildSectionTitle(theme, '高危因素', demo: data.riskIsMock),
                  const SizedBox(height: 8),
                  ..._buildFactorTiles(theme, data),
                  const SizedBox(height: 18),
                  _buildSectionTitle(theme, '历次检查', demo: data.examIsMock),
                  const SizedBox(height: 10),
                  _buildTimeline(theme, data),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 标题栏（标题 + 收起按钮）。
  Widget _buildHeader(ThemeData theme, MainViewModel mainViewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          //Icon(Icons.child_care_outlined, size: 18, color: theme.colorScheme.primary),
          //const SizedBox(width: 6),
          Expanded(
            child: Text(
              '当前儿童',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Tooltip(
            message: '收起',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              hoverColor: theme.colorScheme.primary.withValues(alpha: 0.10),
              highlightColor: theme.colorScheme.primary.withValues(alpha: 0.16),
              onTap: mainViewModel.toggleChildSidebar,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  Icons.keyboard_double_arrow_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 头像 + 姓名 + 性别图标 + 年龄（岁/月/天）。
  Widget _buildProfile(ThemeData theme, ChildSidebarData data) {
    final genderIcon = switch (data.gender) {
      '男' => Icons.male,
      '女' => Icons.female,
      _ => Icons.person_outline,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundImage: _decodeAvatar(data.avatarBase64),
          child: Icon(Icons.child_care_outlined, size: 32, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                data.name.isEmpty ? '未命名儿童' : data.name,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (data.gender.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(genderIcon, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          data.gender,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  if (data.gender.isNotEmpty && data.ageText.isNotEmpty)
                    Text(
                      '·',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  if (data.ageText.isNotEmpty)
                    Text(
                      data.ageText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
              // 早产儿（矫正窗口内）额外展示矫正年龄；实足年龄保留在上方
              if (data.correctedAgeText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Tooltip(
                    message: '早产儿矫正年龄：以预产期（矫正胎龄 40 周）为起点计算，用于体格生长与发育评估；预防接种等按实足年龄',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Wrap(
                        spacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          //Icon(Icons.update, size: 13, color: theme.colorScheme.primary),
                          Text(
                            '矫正年龄 ${data.correctedAgeText}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 五色分级色标 + 综合分级摘要。
  Widget _buildRiskScale(ThemeData theme, ChildSidebarData data) {
    final activeLevels = data.activeLevels;
    final activeColor = _levelColor(data.riskLevel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, '高危五色分级', demo: data.riskIsMock),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final level in HighRiskLevel.values) Expanded(child: _buildRiskBadge(theme, level, activeLevels.contains(level))),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: activeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activeColor.withValues(alpha: 0.35), width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _riskSummary(data),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '依据《高危新生儿分类分级管理专家共识（2023）》评估',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// 五色色标中的单个分级（选中项实心勾选，未选中项弱化）。
  Widget _buildRiskBadge(ThemeData theme, HighRiskLevel level, bool active) {
    final color = _levelColor(level);
    // 浅色（黄色）底上用深色勾，其余深色底用主题前景色，保证可辨识
    final checkColor = color.computeLuminance() > 0.45 ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary;
    return Tooltip(
      message: level.description,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withValues(alpha: 0.14),
              border: Border.all(
                color: active ? color : color.withValues(alpha: 0.30),
                width: active ? 2 : 1,
              ),
            ),
            child: active ? Icon(Icons.check, size: 14, color: checkColor) : null,
          ),
          const SizedBox(height: 4),
          Text(
            level.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontWeight: active ? FontWeight.bold : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// 综合分级摘要文案（紫色为叠加标识，单独说明）。
  String _riskSummary(ChildSidebarData data) {
    final base = '综合分级：${data.riskLevel.label}';
    if (!data.purpleOverlay) return base;
    return '$base，叠加紫色（传染病管理）';
  }

  /// G/P、出生孕周、出生体重、联系电话（无值项不显示）。
  Widget _buildBasicMetrics(ThemeData theme, ChildSidebarData data) {
    final rows = <(String, String?)>[
      ('孕次产次', data.gravidityParity),
      ('出生孕周', data.gestationalAge),
      ('出生体重', data.birthWeight),
      ('联系电话', data.phone),
    ].where((row) => row.$2 != null && row.$2!.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      rows[i].$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$2!,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 分组标题（左侧主题色竖条 + 演示数据角标）。
  Widget _buildSectionTitle(ThemeData theme, String title, {bool demo = false}) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
        if (demo) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '演示数据',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ],
    );
  }

  /// 高危因素卡片列表（左侧色条标识所属五色级别）。
  List<Widget> _buildFactorTiles(ThemeData theme, ChildSidebarData data) {
    return [for (final factor in data.factors) _buildFactorTile(theme, factor)];
  }

  /// 单条高危因素卡片。
  Widget _buildFactorTile(ThemeData theme, HighRiskFactor factor) {
    final color = _levelColor(factor.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          factor.title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          factor.level.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    factor.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 历次检查时间轴。
  Widget _buildTimeline(ThemeData theme, ChildSidebarData data) {
    if (data.exams.isEmpty) {
      return Text(
        '暂无检查记录',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < data.exams.length; i++) _buildTimelineItem(theme, data.exams[i], isLast: i == data.exams.length - 1),
      ],
    );
  }

  /// 单条检查记录（圆点 + 竖线 + 日期/名称/结果）。
  Widget _buildTimelineItem(ThemeData theme, ChildExamRecord exam, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                    border: Border.all(color: theme.colorScheme.surface, width: 1.5),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(exam.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exam.name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exam.result,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 五色分级语义色板：医学色标固定颜色，不随主题切换。
  Color _levelColor(HighRiskLevel level) => switch (level) {
    HighRiskLevel.green => Colors.green.shade700,
    HighRiskLevel.yellow => Colors.yellow.shade800,
    HighRiskLevel.orange => Colors.orange.shade800,
    HighRiskLevel.red => Colors.red.shade700,
    HighRiskLevel.purple => Colors.purple.shade700,
  };

  /// 解析头像 base64（CHILD_PHOTO.AVATAR_IMAGE 为裸 base64）；无效时
  /// 返回 null，回退显示默认儿童图标。
  MemoryImage? _decodeAvatar(String? base64Str) {
    if (base64Str == null || base64Str.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(base64Str));
    } catch (_) {
      return null;
    }
  }

  /// 日期格式化（yyyy-MM-dd）。
  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
