import 'package:client/main.dart';
import 'package:client/models/menu_tree_node.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/menu_icons.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同科室管理）。
enum MenuFormMode {
  /// 未选中任何菜单项目（表单区显示提示）。
  empty,

  /// 编辑选中菜单项目。
  edit,

  /// 新增模式（表单清空，挂载目标为发起新增的节点，null 为顶级）。
  create,
}

/// 菜单管理 ViewModel：左侧「模块→菜单→操作」树（顶级项目为多根
/// 列表），右侧信息表单三态（编辑选中项目 / 新增）。
///
/// 树数据来自 /api/menu/query 的扁平列表、由本类按 parentId 组树、
/// 各层按 ITEM_CODE 顺序排序；
/// 增删成功后整表重拉重建，展开与选中状态尽量保留。每次进入页面
/// loadData 都强制重拉——保证切回本页时数据一致。
class MenuManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入菜单服务（缺省从服务定位器取，测试可覆写）。
  MenuManagementViewModel({MenuService? menuService}) : _menuService = menuService ?? getIt<MenuService>();

  final MenuService _menuService;

  final List<MenuTreeNode> _roots = [];
  final List<Menu> _menus = [];
  bool _loaded = false;
  MenuTreeNode? _selectedNode;
  MenuTreeNode? _createParent;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 顶级节点列表（未加载为空）。
  List<MenuTreeNode> get roots => _roots;

  /// 当前选中树节点（树高亮依据）。
  MenuTreeNode? get selectedNode => _selectedNode;

  /// 当前选中菜单项目（编辑态表单回填；新增模式下保留，取消新增或
  /// 选中新项目即回到其编辑态）。
  Menu? get selectedMenu => _selectedNode?.menu;

  /// 新增挂载目标节点（null 表示顶级项目）。
  MenuTreeNode? get createParent => _createParent;

  /// 右侧表单当前模式。
  MenuFormMode get formMode => _creating ? MenuFormMode.create : (_selectedNode == null ? MenuFormMode.empty : MenuFormMode.edit);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 已加载且库中无任何菜单项目（左侧显示空态引导）。
  bool get isEmpty => _loaded && _menus.isEmpty;

  /// 新增表单顶部的挂载位置说明（如「挂载到：模块「系统管理」」）。
  String get createTargetLabel {
    final parent = _createParent;
    if (parent == null) return '挂载到：顶级（无上级项目）';
    return '挂载到：${_typeLabelOf(parent.menu)}「${parent.name}」';
  }

  /// 编辑表单顶部的归属位置说明（上级项目 / 顶级项目）。
  String get selectedLocationLabel {
    final menu = selectedMenu;
    if (menu == null) return '';
    final parentName = _menus.where((m) => m.id == menu.parentId).map((m) => _typeLabelOf(m) + m.itemName).firstOrNull;
    return parentName != null ? '上级项目：$parentName' : '顶级项目（无上级项目）';
  }

  String _typeLabelOf(Menu menu) {
    final label = menuItemTypeLabels[menu.itemType];
    return label == null ? '' : '「$label」';
  }

  // ---------------- 加载 ----------------

  /// 加载全部菜单项目并组树（进入页面时调用）。每次调用都强制重拉，
  /// 展开与选中状态尽量保留。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshTree();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:MenuManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取全部菜单项目并重建树（选中与新增目标被删时回退）。
  Future<void> _refreshTree() async {
    final menus = await _menuService.queryAll();
    _menus
      ..clear()
      ..addAll(menus);
    final old = List<MenuTreeNode>.from(_roots);
    _roots
      ..clear()
      ..addAll(_buildTree(old));

    final selectedKey = _selectedNode?.key;
    if (selectedKey != null) {
      _selectedNode = _findByKey(_roots, selectedKey);
    }
    final createKey = _createParent?.key;
    if (createKey != null) {
      _createParent = _findByKey(_roots, createKey);
    }
  }

  /// 由扁平列表组树（old 为重建前的旧根列表，保留展开状态）。
  ///
  /// 顶级项目（parentId 为空）为多根，各层子项均按 ITEM_CODE 顺序
  /// 排序（与角色管理权限树同口径）；parentId 指向缺失项目的孤儿
  /// 数据不展示（删除有下级校验、正常流程不会产生）。
  List<MenuTreeNode> _buildTree(List<MenuTreeNode> old) {
    int compare(Menu a, Menu b) => a.itemCode.compareTo(b.itemCode);
    MenuTreeNode buildNode(Menu menu) {
      final node = MenuTreeNode(
        id: menu.id,
        menu: menu,
        expanded: _findByKey(old, 'menu:${menu.id}')?.expanded ?? true,
      );
      final children = _menus.where((m) => m.id != menu.id && m.parentId == menu.id).toList()..sort(compare);
      for (final child in children) {
        node.children.add(buildNode(child));
      }
      return node;
    }

    final roots = _menus.where((m) => m.parentId == null || m.parentId!.isEmpty).toList()..sort(compare);
    return roots.map(buildNode).toList();
  }

  /// 在根列表中递归查找节点（按键）。
  MenuTreeNode? _findByKey(List<MenuTreeNode> roots, String key) {
    for (final root in roots) {
      final hit = root.findByKey(key);
      if (hit != null) return hit;
    }
    return null;
  }

  // ---------------- 交互 ----------------

  /// 选中树节点：进入编辑态。
  void selectNode(MenuTreeNode node) {
    _creating = false;
    _selectedNode = node;
    notifyListeners();
  }

  /// 进入新增模式：右侧表单清空，挂载目标为发起节点（null 为顶级）。
  void startCreate(MenuTreeNode? parent) {
    _createParent = parent;
    _creating = true;
    notifyListeners();
  }

  /// 取消新增，回到选中项目的编辑态（未选中则空态）。
  void cancelCreate() {
    _creating = false;
    notifyListeners();
  }

  /// 切换节点展开/折叠。
  void toggleExpand(MenuTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增菜单项目到挂载目标下（目标为 null 时为顶级项目），成功后
  /// 整表重拉、选中新项目并退出新增模式。
  Future<bool> createMenu({
    required String itemCode,
    required String itemName,
    required String itemType,
    String? menuRoute,
    String? menuIcon,
  }) async {
    final parent = _createParent;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _menuService.create(
        itemCode: itemCode,
        itemName: itemName,
        itemType: itemType,
        parentId: parent?.id,
        menuRoute: menuRoute,
        menuIcon: menuIcon,
      );
      await _refreshTree();
      _selectedNode = _findByKey(_roots, 'menu:${created.id}');
      _creating = false;
      return true;
    } catch (e, st) {
      LogHelper.error('client:MenuManagementViewModel.createMenu', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中菜单项目（changes 键同后端契约：itemCode/itemName/
  /// itemType/menuRoute/menuIcon；上级不可改），成功后整表重拉。
  Future<bool> updateMenu(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _menuService.update(id, changes);
      await _refreshTree();
      _selectedNode = _findByKey(_roots, 'menu:${updated.id}');
      return true;
    } catch (e, st) {
      LogHelper.error('client:MenuManagementViewModel.updateMenu', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除菜单项目，成功后整表重拉；删除选中项目时回退空态。
  Future<bool> deleteMenu(MenuTreeNode node) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _menuService.delete(node.id);
      await _refreshTree();
      return true;
    } catch (e, st) {
      LogHelper.error('client:MenuManagementViewModel.deleteMenu', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
