import 'package:client/main.dart';
import 'package:client/models/admin_division_node.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式。
enum AdminDivisionFormMode {
  /// 未选中任何节点（表单区显示提示）。
  empty,

  /// 编辑选中节点（代码/名称可改，上级只读）。
  edit,

  /// 新增模式（表单清空，上级代码显示新增目标父级，只读）。
  create,
}

/// 行政区划设置 ViewModel：左树懒加载（初始省级，展开时逐级取数）、
/// 右侧信息表单（编辑选中节点 / 新增省级或下级）、级联删除。
///
/// 表内约 70 万行，任何操作都只触碰当前层级的数据；增删改成功后同步
/// 本地树并整树刷新受影响分支，避免整表重载。
class AdminDivisionManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入行政区划服务（缺省从服务定位器取，测试可覆写）。
  AdminDivisionManagementViewModel({AdminDivisionsService? service}) : _service = service ?? getIt<AdminDivisionsService>();

  final AdminDivisionsService _service;

  final List<AdminDivisionNode> _roots = [];
  AdminDivisionNode? _selectedNode;
  AdminDivisionNode? _creatingParentNode;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 根层级（省级）节点列表。
  List<AdminDivisionNode> get roots => _roots;

  /// 当前选中节点（编辑模式数据源、树上高亮依据；新增模式下保留，
  /// 取消新增或选中新节点即回到其编辑态）。
  AdminDivisionNode? get selectedNode => _selectedNode;

  /// 新增模式的目标父节点（null 表示新增省级）。
  AdminDivisionNode? get creatingParentNode => _creatingParentNode;

  /// 右侧表单当前模式。
  AdminDivisionFormMode get formMode => _creating ? AdminDivisionFormMode.create : (_selectedNode == null ? AdminDivisionFormMode.empty : AdminDivisionFormMode.edit);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 加载省级列表（进入页面时调用）。
  Future<bool> loadRoots() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final divisions = await _service.getChildren();
      _roots
        ..clear()
        ..addAll(divisions.map(AdminDivisionNode.fromDivision));
      return true;
    } catch (e, st) {
      LogHelper.error('client:AdminDivisionManagementViewModel.loadRoots', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 选中节点（右侧切换为该节点的编辑表单，同时退出新增模式）。
  void selectNode(AdminDivisionNode node) {
    _creating = false;
    _selectedNode = node;
    notifyListeners();
  }

  /// 进入新增模式：右侧表单清空，上级代码显示 parent（空为省级）。
  void startCreate({AdminDivisionNode? parent}) {
    _creating = true;
    _creatingParentNode = parent;
    notifyListeners();
  }

  /// 取消新增，回到选中节点的编辑态（未选中则空态）。
  void cancelCreate() {
    _creating = false;
    notifyListeners();
  }

  /// 展开/折叠节点：首次展开且后端标记有下级时先懒加载子级。
  Future<bool> toggleExpand(AdminDivisionNode node) async {
    if (!node.expanded && node.hasChildren && !node.childrenLoaded) {
      try {
        final children = await _service.getChildren(parentCode: node.code);
        node.children
          ..clear()
          ..addAll(children.map(AdminDivisionNode.fromDivision));
        node.childrenLoaded = true;
      } catch (e, st) {
        LogHelper.error('client:AdminDivisionManagementViewModel.toggleExpand', e, st);
        _errorMsg = _messageOf(e);
        notifyListeners();
        return false;
      }
    }
    node.expanded = !node.expanded;
    notifyListeners();
    return true;
  }

  /// 新增行政区划（parent 为空表示省级），成功后插入本地树并展开父节点。
  Future<bool> createDivision({AdminDivisionNode? parent, required String code, required String name}) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _service.create(code: code, name: name, parentCode: parent?.code);
      var node = AdminDivisionNode.fromDivision(created);
      if (parent == null) {
        var index = _roots.indexWhere((c) => c.code.compareTo(node.code) > 0);
        if (index < 0) index = _roots.length;
        _roots.insert(index, node);
      } else if (parent.childrenLoaded) {
        // 父级子级已加载过：本地按序插入即可
        parent.insertChild(node);
        parent.expanded = true;
      } else {
        // 父级子级未加载过（从未展开）：整体重新拉取（服务端已含新
        // 节点），避免本地树只见新节点不见原有子级
        final children = await _service.getChildren(parentCode: parent.code);
        parent.children
          ..clear()
          ..addAll(children.map(AdminDivisionNode.fromDivision));
        parent.childrenLoaded = true;
        parent.hasChildren = true;
        parent.expanded = true;
        // 选中树内真实节点（拉取生成的对象），后续改名才能同步到树
        for (final c in parent.children) {
          if (c.code == node.code) {
            node = c;
            break;
          }
        }
      }
      _selectedNode = node;
      // 新增成功后退出新增模式，右侧切换为新节点的编辑表单
      _creating = false;
      _creatingParentNode = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:AdminDivisionManagementViewModel.createDivision', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中节点（名称与编码均可改；改编码时后端级联更新下级父引用，
  /// 本地树同步代码与直接子级父引用，并按新代码重新排序节点位置）。
  Future<bool> updateDivision(AdminDivisionNode node, {String? newCode, required String name}) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _service.update(code: node.code, newCode: newCode, name: name);
      node.name = updated.name;
      if (updated.code != node.code) {
        final parent = _findParentOf(node.code);
        node.changeCode(updated.code);
        if (parent != null) {
          _reposition(parent.children, node);
        } else {
          _reposition(_roots, node);
        }
      }
      return true;
    } catch (e, st) {
      LogHelper.error('client:AdminDivisionManagementViewModel.updateDivision', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 查询子树规模（含自身），删除确认提示用。
  Future<int> subtreeCount(AdminDivisionNode node) async {
    return _service.getSubtreeCount(node.code);
  }

  /// 级联删除节点及其全部下级，成功后从本地树移除。
  Future<bool> deleteDivision(AdminDivisionNode node) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _service.delete(node.code);
      _removeFromTree(node);
      return true;
    } catch (e, st) {
      LogHelper.error('client:AdminDivisionManagementViewModel.deleteDivision', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 从本地树移除节点；若选中节点在被移除的子树内（含正是被删节点）
  /// 则清空选中（须在摘除前判断，摘除后子树引用已断开）；父节点无剩余
  /// 子级时回退展开标记（箭头消失，下次有子级时重新懒加载）。
  void _removeFromTree(AdminDivisionNode node) {
    final parent = _findParentOf(node.code);
    final selected = _selectedNode;
    if (selected != null && node.find(selected.code) != null) {
      _selectedNode = null;
    }
    void removeFrom(List<AdminDivisionNode> list) {
      list.removeWhere((n) => n.code == node.code);
      for (final n in list) {
        removeFrom(n.children);
      }
    }

    removeFrom(_roots);
    if (parent != null && parent.children.isEmpty) {
      parent.hasChildren = false;
      parent.expanded = false;
      parent.childrenLoaded = false;
    }
    // 防御：删除动作只能来自选中态，但保持状态机一致仍复位新增标记
    _creating = false;
    _creatingParentNode = null;
  }

  /// 在本地树中查找某节点的父节点（顶级节点返回 null）。
  AdminDivisionNode? _findParentOf(String code) {
    AdminDivisionNode? walk(List<AdminDivisionNode> list) {
      for (final n in list) {
        if (n.children.any((c) => c.code == code)) return n;
        final r = walk(n.children);
        if (r != null) return r;
      }
      return null;
    }

    return walk(_roots);
  }

  /// 把节点在同级列表中移动到新代码对应的升序位置（改码后调用）。
  void _reposition(List<AdminDivisionNode> list, AdminDivisionNode node) {
    list.remove(node);
    var index = list.indexWhere((c) => c.code.compareTo(node.code) > 0);
    if (index < 0) index = list.length;
    list.insert(index, node);
  }

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
