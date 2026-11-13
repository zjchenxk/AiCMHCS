import 'package:client/main.dart';
import 'package:client/models/dict_tree_node.dart';
import 'package:client/services/dict_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 字典管理 ViewModel：左侧数据字典树（顶级字典为多根列表），右侧为
/// 选中字典的数据项列表。
///
/// 树数据来自 /api/dict/query 的扁平列表、由本类按 parentId 组树、
/// 各层按显示顺序（未设置靠后）→字典编码排序；右侧数据项随选中字典
/// 懒加载、按显示顺序（未设置靠后）→项目编码排序。增删成功后整表重
/// 拉，展开与选中状态尽量保留。每次进入页面 loadData 都强制重拉——
/// 保证切回本页时数据一致。
class DictManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入字典服务（缺省从服务定位器取，测试可覆写）。
  DictManagementViewModel({DictService? dictService}) : _dictService = dictService ?? getIt<DictService>();

  final DictService _dictService;

  final List<DictTreeNode> _roots = [];
  final List<Dict> _dicts = [];
  final List<DictItem> _items = [];
  bool _loaded = false;
  DictTreeNode? _selectedNode;
  DictTreeNode? _createParent;
  bool _loading = false;
  bool _itemsLoading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 顶级节点列表（未加载为空）。
  List<DictTreeNode> get roots => _roots;

  /// 当前选中树节点（树高亮依据）。
  DictTreeNode? get selectedNode => _selectedNode;

  /// 当前选中数据字典（右侧数据项列表标题回填）。
  Dict? get selectedDict => _selectedNode?.dict;

  /// 新增挂载目标节点（null 表示顶级字典）。
  DictTreeNode? get createParent => _createParent;

  /// 当前选中字典的数据项列表（未选中字典为空）。
  List<DictItem> get items => _items;

  /// 首屏加载中。
  bool get loading => _loading;

  /// 右侧数据项加载中。
  bool get itemsLoading => _itemsLoading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 已加载且本院未配置任何数据字典（左侧显示空态引导）。
  bool get isEmpty => _loaded && _dicts.isEmpty;

  /// 新增表单顶部的挂载位置说明。
  String get createTargetLabel {
    final parent = _createParent;
    if (parent == null) return '挂载到：顶级（无上级字典）';
    return '挂载到：字典「${parent.name}」';
  }

  // ---------------- 加载 ----------------

  /// 加载全部数据字典并组树（进入页面时调用）。每次调用都强制重拉，
  /// 展开与选中状态尽量保留，选中字典的数据项随之重拉。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshTree();
      _loaded = true;
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取全部数据字典并重建树（选中与新增目标被删时回退）。
  Future<void> _refreshTree() async {
    final dicts = await _dictService.queryAll();
    _dicts
      ..clear()
      ..addAll(dicts);
    final old = List<DictTreeNode>.from(_roots);
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
  /// 顶级字典（parentId 为空）为多根，各层子项均按显示顺序（未设置
  /// 靠后）→字典编码排序；parentId 指向缺失字典的孤儿数据不展示
  /// （删除有下级校验、正常流程不会产生）。
  List<DictTreeNode> _buildTree(List<DictTreeNode> old) {
    int compare(Dict a, Dict b) => _compareOrderAndCode(a.displayOrder, b.displayOrder, a.dictCode, b.dictCode);

    DictTreeNode buildNode(Dict dict) {
      final node = DictTreeNode(
        id: dict.id,
        dict: dict,
        expanded: _findByKey(old, 'dict:${dict.id}')?.expanded ?? true,
      );
      final children = _dicts.where((d) => d.id != dict.id && d.parentId == dict.id).toList()..sort(compare);
      for (final child in children) {
        node.children.add(buildNode(child));
      }
      return node;
    }

    final roots = _dicts.where((d) => d.parentId == null || d.parentId!.isEmpty).toList()..sort(compare);
    return roots.map(buildNode).toList();
  }

  /// 在根列表中递归查找节点（按键）。
  DictTreeNode? _findByKey(List<DictTreeNode> roots, String key) {
    for (final root in roots) {
      final hit = root.findByKey(key);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 拉取当前选中字典的数据项（按显示顺序排序，未设置靠后）。
  ///
  /// 选中字典在等待期间被切换时丢弃过期结果（懒加载竞态防护）。
  Future<void> _refreshItems() async {
    final dict = _selectedNode?.dict;
    final requestedId = dict?.id;
    if (requestedId == null) {
      _items.clear();
      notifyListeners();
      return;
    }
    _itemsLoading = true;
    notifyListeners();
    try {
      final items = await _dictService.queryItems(requestedId);
      if (_selectedNode?.dict.id != requestedId) return;
      items.sort((a, b) => _compareOrderAndCode(a.displayOrder, b.displayOrder, a.itemCode, b.itemCode));
      _items
        ..clear()
        ..addAll(items);
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel._refreshItems', e, st);
      _errorMsg = _messageOf(e);
    } finally {
      _itemsLoading = false;
      notifyListeners();
    }
  }

  // ---------------- 交互 ----------------

  /// 选中树节点：右侧切换为该字典的数据项列表。
  void selectNode(DictTreeNode node) {
    if (identical(_selectedNode, node)) return;
    _selectedNode = node;
    notifyListeners();
    _refreshItems();
  }

  /// 进入新增字典模式（parent 为 null 时为顶级字典）；挂载目标供
  /// 新增表单展示位置说明、新增成功后落库挂载。
  void startCreate(DictTreeNode? parent) {
    _createParent = parent;
    notifyListeners();
  }

  /// 切换节点展开/折叠。
  void toggleExpand(DictTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  // ---------------- 字典增删改 ----------------

  /// 新增数据字典到挂载目标下（目标为 null 时为顶级字典），成功后整表
  /// 重拉、选中新字典并刷新右侧数据项。
  Future<bool> createDict({
    required String dictCode,
    required String dictName,
    String? displayOrder,
  }) async {
    final parent = _createParent;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _dictService.create(
        dictCode: dictCode,
        dictName: dictName,
        parentId: parent?.id,
        displayOrder: displayOrder,
      );
      await _refreshTree();
      _selectedNode = _findByKey(_roots, 'dict:${created.id}');
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.createDict', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中数据字典（changes 键同后端契约：dictCode/dictName/
  /// displayOrder；上级不可改），成功后整表重拉。
  Future<bool> updateDict(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _dictService.update(id, changes);
      await _refreshTree();
      _selectedNode = _findByKey(_roots, 'dict:${updated.id}');
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.updateDict', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除数据字典，成功后整表重拉；删除选中字典时回退空态并清空右侧。
  Future<bool> deleteDict(DictTreeNode node) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _dictService.delete(node.id);
      await _refreshTree();
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.deleteDict', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 数据项增删改 ----------------

  /// 新增数据项到当前选中字典，成功后重拉右侧列表。
  Future<bool> createItem({
    required String itemCode,
    required String itemValue,
    String? displayOrder,
    String isDefault = '0',
  }) async {
    final dict = _selectedNode?.dict;
    if (dict == null) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _dictService.createItem(
        dictId: dict.id,
        itemCode: itemCode,
        itemValue: itemValue,
        displayOrder: displayOrder,
        isDefault: isDefault,
      );
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.createItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改数据项（changes 键同后端契约：itemCode/itemValue/displayOrder），
  /// 成功后重拉右侧列表。
  Future<bool> updateItem(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _dictService.updateItem(id, changes);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.updateItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除数据项，成功后重拉右侧列表。
  Future<bool> deleteItem(DictItem item) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _dictService.deleteItem(item.id);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.deleteItem', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 设置数据项为所属字典的默认项（同字典内原默认项自动取消），成功后
  /// 重拉右侧列表。
  Future<bool> setItemDefault(DictItem item) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _dictService.setItemDefault(item.id);
      await _refreshItems();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DictManagementViewModel.setItemDefault', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------- 通用 ----------------

  /// 显示顺序比较（未设置靠后），顺序相同时回退到编码比较。
  int _compareOrderAndCode(String? orderA, String? orderB, String codeA, String codeB) {
    final a = int.tryParse(orderA ?? '');
    final b = int.tryParse(orderB ?? '');
    if (a == null || b == null) {
      if (a == b) return codeA.compareTo(codeB); // 双方均未设置
      return a == null ? 1 : -1;
    }
    if (a != b) return a.compareTo(b);
    return codeA.compareTo(codeB);
  }

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
