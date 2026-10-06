import 'package:aicmhcs_client/providers/theme_provider.dart';
import 'package:aicmhcs_client/utils/theme_color_mapper_util.dart';
import 'package:aicmhcs_client/utils/theme_data_util.dart';
import 'package:aicmhcs_client/views/help/help_center_page.dart';
import 'package:aicmhcs_client/widgets/glass_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:aicmhcs_client/models/login_user.dart';
import 'package:aicmhcs_client/models/menu_item.dart';
import 'package:aicmhcs_client/providers/font_provider.dart';
import 'package:aicmhcs_client/routes/menu_routes.dart';
import 'package:aicmhcs_client/view_models/login/login_view_model.dart';
import 'package:aicmhcs_client/view_models/main/main_view_model.dart';
import 'package:aicmhcs_client/views/login/login_page.dart';
import 'package:aicmhcs_client/views/main/change_password_dialog.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:ui';

import 'package:provider/provider.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _searchController = TextEditingController();
  // 用户菜单控制器
  final MenuController _userMenuController = MenuController();
  // 设置菜单控制器
  final MenuController _settingsMenuController = MenuController();
  // 帮助菜单控制器
  final MenuController _helpMenuController = MenuController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // 背景采用当前主题的 PrimaryContainer（Material 3 规范）
      backgroundColor: theme.colorScheme.primaryContainer,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(theme),
                  Expanded(child: _buildContentArea(theme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 毛玻璃容器
  Widget _glassPanel({required Widget child, double blur = 20, required Color color, required BorderRadius radius}) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),

          // ===== 新增：透明 Material，让 ink 效果画在面板底色之上 =====
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }

  // 顶部栏
  Widget _buildHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: _glassPanel(
        radius: BorderRadius.zero,
        color: theme.colorScheme.primaryContainer,
        child: Row(
          children: [
            // LOGO 及系统名称（可多行，字号分层）
            _buildLogo(theme),
            // 登录用户信息
            Expanded(child: _buildLoginUserInfoBar(theme)),
            // 用户 / 设置 / 帮助
            _buildHeaderActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(ThemeData theme) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/images/logo.svg',
            width: 44,
            height: 44,
            colorMapper: ThemeColorMapper(primary: theme.colorScheme.primary),
          ),

          const SizedBox(width: 10),
          // 多行文字、字号分层
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AiCMHCS',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 22,
                    letterSpacing: 1.5,
                    height: 1.1,
                  ),
                ),
                Text(
                  '智慧儿童心理保健系统',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 14,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginUserInfoBar(ThemeData theme) {
    return Selector<MainViewModel, LoginUser>(
      selector: (context, mainViewModel) => mainViewModel.loginUser,
      builder: (context, loginUser, _) {
        final items = <(String, String?)>[
          ('当前医院', loginUser.organName),
          ('当前院区', loginUser.branchName),
          ('当前科室', loginUser.deptName),
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '欢迎回来！',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
              for (final (label, value) in items)
                if (value != null && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$label:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderActions(ThemeData theme) {
    return Selector<MainViewModel, String>(
      selector: (context, mainViewModel) => mainViewModel.userName,
      builder: (context, userName, _) {
        return Row(
          children: [
            _buildHeaderUserMenu(theme, userName),
            _buildHeaderSettingsMenu(theme),
            _buildHeaderHelpMenu(theme),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }

  // 登录用户管理菜单
  Widget _buildHeaderUserMenu(ThemeData theme, String userName) {
    return MenuAnchor(
      controller: _userMenuController,
      // 菜单整体样式：白底、圆角、描边，与系统视觉一致
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.key_outlined, size: 18, color: theme.colorScheme.primary),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _showChangePasswordDialog(context),
          child: Text(
            '修改密码',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
        const Divider(height: 9, thickness: 0.5),

        MenuItemButton(
          leadingIcon: Icon(Icons.swap_horiz, size: 18, color: theme.colorScheme.primary),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _showSwitchDeptDialog(context, theme),
          child: Text(
            '切换科室',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
        const Divider(height: 9, thickness: 0.5),

        MenuItemButton(
          leadingIcon: Icon(Icons.logout, size: 18, color: theme.colorScheme.error),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _logout(context),
          child: Text(
            '注销退出',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(10),
        // 显式三态高亮色
        hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
        highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                userName.characters.first,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              userName,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  // 设置菜单
  Widget _buildHeaderSettingsMenu(ThemeData theme) {
    // 5 档字体缩放选项
    final List<double> fontScaleOptions = const [1.0, 1.25, 1.5, 1.75, 2.0];

    // 获取当前主题名（watch 保证切换主题后菜单勾选刷新）
    final currentThemeName = context.watch<ThemeProvider>().currentThemeName;
    // 所有可用主题名（来自 AppThemes，动态获取）
    final themeNames = context.read<ThemeProvider>().themeNames;
    // 获取当前字体缩放比例（watch 保证切换后菜单勾选刷新）
    final fontScale = context.watch<FontProvider>().fontScale;

    return MenuAnchor(
      controller: _settingsMenuController,
      // 菜单样式与用户菜单保持一致
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        // 设置字体菜单
        SubmenuButton(
          leadingIcon: Icon(Icons.format_size, size: 18, color: theme.colorScheme.primary),
          style: SubmenuButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          // 子菜单
          menuChildren: [
            for (final option in fontScaleOptions)
              MenuItemButton(
                style: MenuItemButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                // 设置并缓存字体比例（FontProvider 内部持久化 + 通知全局刷新）
                onPressed: () => context.read<FontProvider>().setFontScale(option),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 当前比例 → 勾选标记
                    SizedBox(
                      width: 20,
                      child: option == fontScale ? Icon(Icons.check, size: 18, color: theme.colorScheme.primary) : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(option * 100).round()}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: option == fontScale ? FontWeight.bold : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Text(
            '设置字体',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),

        // 设置主题菜单
        SubmenuButton(
          leadingIcon: Icon(Icons.palette_outlined, size: 18, color: theme.colorScheme.primary),
          style: SubmenuButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          menuChildren: [
            for (final name in themeNames)
              MenuItemButton(
                style: MenuItemButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                // 切换主题：ThemeProvider 内部持久化 + notifyListeners，
                // MyApp 的 watch 触发 MaterialApp 重建 → 全 UI 换主题
                onPressed: () => context.read<ThemeProvider>().switchTheme(name),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 当前主题 → 勾选标记
                    SizedBox(
                      width: 20,
                      child: name == currentThemeName ? Icon(Icons.check, size: 18, color: theme.colorScheme.primary) : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: name == currentThemeName ? FontWeight.bold : FontWeight.w400,
                      ),
                    ),
                    // 预览色块：直接展示该主题的主色，更直观
                    const SizedBox(width: 12),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppThemes.themes[name]?.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Text(
            '设置主题',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ],
      // anchor：复用你原有的三态高亮样式（与用户头像一致）
      builder: (context, controller, child) => Tooltip(
        message: '设置',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
          highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Icon(
          Icons.settings_outlined,
          color: theme.colorScheme.onPrimaryContainer,
          size: 22,
        ),
      ),
    );
  }

  // 帮助菜单
  Widget _buildHeaderHelpMenu(ThemeData theme) {
    return MenuAnchor(
      controller: _helpMenuController,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(Icons.help_outline, size: 18, color: theme.colorScheme.primary),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          // 打开帮助中心：由 MainViewModel 驱动内容区
          onPressed: () {
            context.read<MainViewModel>().openHelpCenter();
          },
          child: Text(
            '帮助中心',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
        const Divider(height: 9, thickness: 0.5),

        MenuItemButton(
          leadingIcon: Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: () => _showAboutDialog(theme),
          child: Text(
            '关于',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      ],
      // anchor：与另外两个按钮一致的三态高亮
      builder: (context, controller, child) => Tooltip(
        message: '帮助',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
          highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Icon(
          Icons.help_outline,
          color: theme.colorScheme.onPrimaryContainer,
          size: 22,
        ),
      ),
    );
  }

  // 功能菜单侧边栏
  Widget _buildSidebar(ThemeData theme) {
    return Consumer<MainViewModel>(
      child: _buildSearchField(theme), //搜索框不依赖任何状态 → 缓存
      builder: (context, mainViewModel, child) {
        final width = mainViewModel.collapsed ? 64.0 : 240.0;
        final menus = mainViewModel.filteredMenus;
        final isWide = !mainViewModel.collapsed; //立即切换，不等动画

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.all(8),
          width: width,
          child: _glassPanel(
            radius: BorderRadius.zero,
            color: theme.colorScheme.primaryContainer,
            child: Column(
              children: [
                // 标题 + 折叠按钮
                _buildCollapseHeader(theme, mainViewModel, isWide),

                // 搜索框（collapsed 时隐藏，child 直接复用不重建）
                if (isWide) child!,

                // 菜单列表
                Expanded(
                  child: isWide
                      // 展开态：给它完整的 207px 内部宽度，
                      // 面板还没拉开时由 ClipRRect 裁掉，不会溢出
                      ? OverflowBox(
                          alignment: AlignmentDirectional.centerStart,
                          minWidth: 0,
                          maxWidth: 207, // 240 − margin16 − border1 − listPadding16
                          child: SizedBox(
                            width: 207,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              itemCount: menus.length,
                              itemBuilder: (context, index) => _buildMenuItem(theme, mainViewModel, menus[index], [], true),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          itemCount: menus.length,
                          itemBuilder: (context, index) => _buildMenuItem(theme, mainViewModel, menus[index], [], false),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapseHeader(ThemeData theme, MainViewModel mainViewModel, bool isWide) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (isWide)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '功能菜单',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          InkWell(
            borderRadius: BorderRadius.circular(10),
            // 显式三态高亮色
            hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
            highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
            onTap: () => mainViewModel.toggleCollapse(),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                mainViewModel.collapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
                color: theme.colorScheme.onPrimaryContainer,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchController,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
        decoration: InputDecoration(
          hintText: '搜索功能菜单...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5)),
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6), size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          filled: true,
          fillColor: theme.colorScheme.surface.withValues(alpha: 0.5),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
        onChanged: (v) => context.read<MainViewModel>().setSearchKeyword(v),
      ),
    );
  }

  Widget _buildMenuItem(ThemeData theme, MainViewModel mainViewModel, MenuItem menu, List<String> parentPath, bool isWide) {
    final hasChildren = menu.children.isNotEmpty;
    final expanded = mainViewModel.isExpanded(menu.id);
    final selected = mainViewModel.selectedMenuId == menu.id;
    final path = [...parentPath, menu.title];

    if (!isWide) {
      return Tooltip(
        message: menu.title,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          // 显式三态高亮色
          hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
          highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
          splashColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.20),
          onTap: () {
            hasChildren ? mainViewModel.toggleExpand(menu.id) : mainViewModel.selectMenu(menu, path);
          },
          child: Container(
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                menu.icon,
                size: 20,
                color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          // 显式三态高亮色
          hoverColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
          highlightColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.28),
          splashColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.20),
          onTap: () {
            hasChildren ? mainViewModel.toggleExpand(menu.id) : mainViewModel.selectMenu(menu, path);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  menu.icon,
                  size: 18,
                  color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    menu.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasChildren)
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 二级子菜单
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: expanded || mainViewModel.searchKeyword.isNotEmpty ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: menu.children.map((c) => _buildMenuItem(theme, mainViewModel, c, path, isWide)).toList(),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // 中央内容区（白色圆角背景）
  Widget _buildContentArea(ThemeData theme) {
    return Selector<MainViewModel, String?>(
      // 只监听 selectedMenuId：切换菜单时才重建，这样搜索输入 / 折叠展开均不会触发本区域重建
      selector: (context, mainViewModel) => mainViewModel.selectedMenuId,
      builder: (context, selectedMenuId, _) {
        // 在 builder 内读取其他关联数据（不会建立订阅）
        final mainViewModel = context.read<MainViewModel>();

        // 处理帮助中心菜单（不属于 menuRoutes 的功能页）
        if (selectedMenuId == 'help-center') {
          return Container(
            margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      Icon(Icons.help_outline, color: theme.colorScheme.primary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '帮助中心',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24, thickness: 0.5),
                const Expanded(child: HelpCenterPage()),
              ],
            ),
          );
        }

        final menu = mainViewModel.findMenuById(selectedMenuId);
        final route = menu?.route;

        //根据 route 取页面构造器
        Widget workspace;
        final builder = route != null ? menuRoutes[route] : null;
        if (builder != null) {
          workspace = KeyedSubtree(
            // 用菜单 id 作为 key：切换菜单时旧页面销毁、新页面重建
            key: ValueKey(menu!.id),
            child: builder(context, mainViewModel.loginUser, mainViewModel.child),
          );
        } else {
          // 未注册路由 / 未选择菜单时的工作区占位
          workspace = Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.dashboard_customize, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  selectedMenuId == null ? '请从左侧选择功能菜单' : '当前功能：${mainViewModel.selectedMenuTitle ?? ''}',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface, // 白色（跟随主题）
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Expanded(child: workspace),
        );
      },
    );
  }

  // 修改密码
  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final mainViewModel = context.read<MainViewModel>();
    final username = mainViewModel.loginUser.userCode; // 或 userName，取决于服务端登录名

    final changed = await ChangePasswordDialog.show(context, username: username);
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('密码修改成功，请重新登录'),
        ),
      );
      // 等保要求：密码修改后强制重新登录
      _logout(context);
    }
  }

  // 切换科室
  Future<void> _showSwitchDeptDialog(BuildContext context, ThemeData theme) async {
    final mainViewModel = context.read<MainViewModel>();

    final selected = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        String currentDeptId = mainViewModel.loginUser.deptId; // 弹窗内的局部选中态

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: GlassPanel(
                blur: 24,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Row(
                        children: [
                          Icon(Icons.swap_horiz, color: theme.colorScheme.primary, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            '切换科室',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 单选列表
                      Flexible(
                        child: RadioGroup<String>(
                          groupValue: currentDeptId,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => currentDeptId = value);
                            }
                          },
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final (deptId, deptName) in mainViewModel.availableDepts)
                                RadioListTile<String>(
                                  value: deptId,
                                  dense: true,
                                  activeColor: theme.colorScheme.primary,
                                  title: Text(
                                    deptName,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 按钮组
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(
                              '取消',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () {
                              final dept = mainViewModel.availableDepts.firstWhere((d) => d.$1 == currentDeptId, orElse: () => ('', ''));
                              if (dept.$1.isNotEmpty) {
                                Navigator.of(dialogContext).pop(dept);
                              }
                            },
                            child: Text(
                              '确定',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
                            ),
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
      },
    );

    if (selected != null && selected.$1 != mainViewModel.loginUser.deptId) {
      mainViewModel.switchDepartment(selected.$1, selected.$2);
    }
  }

  // 重新登录
  void _logout(BuildContext context) {
    // 清空登录页的输入状态（用户名/密码/科室/错误提示）
    context.read<LoginViewModel>().reset();

    // 清理主界面状态
    context.read<MainViewModel>().resetForRelogin();

    // 跳转登录页并清空路由栈；rootNavigator 保证即使将来出现嵌套 Navigator 也操作的是根栈
    Navigator.of(context, rootNavigator: true).pushReplacement(MaterialPageRoute(builder: (context) => const LoginPage()));
  }

  // 关于对话框（毛玻璃风格）
  Future<void> _showAboutDialog(ThemeData theme) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent, // 关键：去掉 Dialog 自带的不透明白底
        child: ClipRRect(
          // 毛玻璃必须配合裁切，否则模糊溢出圆角
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            // 毛玻璃核心：对对话框背后的遮罩+主界面取高斯模糊
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              // 半透明面板：透出被模糊的背景，同时保证文字可读
              color: theme.colorScheme.surface.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo（同主界面左上角，跟随主题色）
                    SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: 72,
                      height: 72,
                      colorMapper: ThemeColorMapper(primary: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AiCMHCS',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '智慧儿童心理保健系统',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 14),
                    Text(
                      '©2026 Chenxk Software Studio. All rights reserved.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 20),
                    // 关闭按钮（FilledButton 在毛玻璃上比 TextButton 更清晰）
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(120, 40),
                      ),
                      child: Text(
                        '关闭',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
