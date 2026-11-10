import 'package:client/main.dart';
import 'package:client/models/department_tree_node.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/department_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同院区管理）。
enum DepartmentFormMode {
  /// 未选中任何科室（表单区显示提示）。
  empty,

  /// 编辑选中科室。
  edit,

  /// 新增模式（表单清空，挂载目标为发起新增的节点）。
  create,
}

/// 科室管理 ViewModel：绑定当前登录用户的所属医院（hospId），左侧
/// 「医院→院区→科室→下级科室」树（医院未设置院区时科室直挂医院根，
/// 医院已设置院区时顶级科室挂院区下、医院根不提供新增入口），右侧
/// 信息表单三态（编辑选中科室 / 新增）。
///
/// 医院根为当前登录用户所属医院（不展示下级医院）；树数据来自该院
/// 的院区列表 + 科室扁平列表、由本类组树；增删成功后整表重拉重建，
/// 展开与选中状态尽量保留。每次进入页面 loadData 都强制重拉——
/// 院区管理等兄弟页面可能已改动院区数据，跳过缓存才能保证切回时
/// 数据一致（展开与选中状态经 _refreshTree 保留）。
class DepartmentManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入院区与科室服务（缺省从服务定位器取，测试可覆写）。
  DepartmentManagementViewModel({
    CampusService? campusService,
    DepartmentService? departmentService,
  }) : _campusService = campusService ?? getIt<CampusService>(),
       _departmentService = departmentService ?? getIt<DepartmentService>();

  final CampusService _campusService;
  final DepartmentService _departmentService;

  DepartmentTreeNode? _root;
  final List<Campus> _campuses = [];
  final List<Department> _departments = [];
  String? _hospId;
  String _hospName = '';
  bool _loaded = false;
  DepartmentTreeNode? _selectedNode;
  DepartmentTreeNode? _createParent;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 当前树根（医院节点，未加载为 null）。
  DepartmentTreeNode? get root => _root;

  /// 当前选中树节点（科室节点；树高亮依据）。
  DepartmentTreeNode? get selectedNode => _selectedNode;

  /// 当前选中科室（编辑态表单回填、树高亮依据；新增模式下保留，
  /// 取消新增或选中新科室即回到其编辑态）。
  Department? get selectedDepartment => _selectedNode?.type == DepartmentTreeNodeType.department ? _selectedNode!.department : null;

  /// 新增挂载目标节点（医院未设置院区时的医院根 / 院区 / 上级科室）。
  DepartmentTreeNode? get createParent => _createParent;

  /// 右侧表单当前模式。
  DepartmentFormMode get formMode => _creating ? DepartmentFormMode.create : (_selectedNode == null ? DepartmentFormMode.empty : DepartmentFormMode.edit);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 当前绑定的医院 ID（未加载为 null）。
  String? get hospId => _hospId;

  /// 登录用户未设置所属医院（页面据此显示引导提示而非空树）。
  bool get unbound => _loaded && (_hospId == null || _hospId!.isEmpty);

  /// 医院已设置院区（为真时医院根不提供新增科室入口，须挂院区下）。
  bool get hasCampuses => _campuses.isNotEmpty;

  /// 新增表单顶部的挂载位置说明（如「挂载到：院区「主院区」」）。
  String get createTargetLabel {
    final parent = _createParent;
    if (parent == null) return '';
    final typeLabel = switch (parent.type) {
      DepartmentTreeNodeType.department => '上级科室',
      DepartmentTreeNodeType.campus => '院区',
      DepartmentTreeNodeType.hospital => '医院',
    };
    return '挂载到：$typeLabel「${parent.name}」';
  }

  /// 编辑表单顶部的归属位置说明（上级科室 / 所属院区 / 所属医院）。
  String get selectedLocationLabel {
    final dept = selectedDepartment;
    if (dept == null) return '';
    final parentName = _departments.where((d) => d.id == dept.parentId).map((d) => d.name).firstOrNull;
    if (parentName != null) return '上级科室：$parentName';
    if (dept.campusId != null) {
      final campusName = _campuses.where((c) => c.id == dept.campusId).map((c) => c.name).firstOrNull;
      if (campusName != null) return '所属院区：$campusName';
    }
    return '所属医院：${_hospName.isEmpty ? '当前医院' : _hospName}';
  }

  // ---------------- 加载 ----------------

  /// 加载登录用户所属医院的院区与科室并组树（进入页面时调用）。
  ///
  /// hospId 为空视为未绑定：清空树并置提示；每次调用都强制重拉
  /// （院区管理等兄弟页面可能已改动院区/科室数据，切回本页须重新
  /// 组树），展开与选中状态尽量保留。
  Future<bool> loadData(String? hospId, String? hospName) async {
    final h = hospId?.trim() ?? '';

    _hospId = h;
    _hospName = hospName?.trim() ?? '';
    if (h.isEmpty) {
      _loaded = true;
      _root = null;
      _campuses.clear();
      _departments.clear();
      _selectedNode = null;
      _createParent = null;
      _creating = false;
      _errorMsg = '当前登录用户未设置所属医院，无法管理科室';
      notifyListeners();
      return false;
    }

    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshTree();
      _loaded = true;
      return true;
    } catch (e, st) {
      LogHelper.error('client:DepartmentManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取当前医院的院区与科室并重建树（选中与新增目标被删时回退）。
  Future<void> _refreshTree() async {
    final campuses = await _campusService.getByHospital(_hospId!);
    final departments = await _departmentService.getByHospital(_hospId!);
    _campuses
      ..clear()
      ..addAll(campuses);
    _departments
      ..clear()
      ..addAll(departments);
    _root = _buildTree(_root);

    final selectedKey = _selectedNode?.key;
    if (selectedKey != null) {
      _selectedNode = _root?.findByKey(selectedKey);
    }
    final createKey = _createParent?.key;
    if (createKey != null) {
      _createParent = _root?.findByKey(createKey);
    }
  }

  /// 由院区与科室扁平列表组树（old 为重建前的旧树，保留展开状态）。
  ///
  /// 结构：医院根 → 院区节点（医院已设置院区时）→ 顶级科室（按
  /// CAMPUS_ID 挂对应院区，医院未设置院区时直挂医院根）→ 下级科室
  /// （按 PARENT_ID 递归）。CAMPUS_ID 指向缺失院区的顶级科室兜底挂
  /// 医院根（规则破坏的历史数据如实展示）；PARENT_ID 指向缺失科室的
  /// 孤儿下级不展示（删除有下级校验、正常流程不会产生）。
  DepartmentTreeNode _buildTree(DepartmentTreeNode? old) {
    final root = DepartmentTreeNode(
      type: DepartmentTreeNodeType.hospital,
      id: _hospId!,
      name: _hospName.isEmpty ? '所属医院' : _hospName,
      expanded: old?.expanded ?? true,
    );
    final topDepts = _departments.where((d) => d.parentId == null || d.parentId!.isEmpty).toList();

    if (_campuses.isNotEmpty) {
      for (final campus in _campuses) {
        final campusNode = DepartmentTreeNode(
          type: DepartmentTreeNodeType.campus,
          id: campus.id,
          name: campus.name,
          campusId: campus.id,
          expanded: old?.findByKey('campus:${campus.id}')?.expanded ?? true,
        );
        for (final dept in topDepts.where((d) => d.campusId == campus.id)) {
          campusNode.children.add(_buildDeptNode(dept, old));
        }
        root.children.add(campusNode);
      }
      final campusIds = _campuses.map((c) => c.id).toSet();
      final orphans = topDepts.where(
        (d) => d.campusId == null || !campusIds.contains(d.campusId),
      );
      for (final dept in orphans) {
        root.children.add(_buildDeptNode(dept, old));
      }
    } else {
      for (final dept in topDepts) {
        root.children.add(_buildDeptNode(dept, old));
      }
    }
    return root;
  }

  /// 递归构建科室节点及其下级。
  DepartmentTreeNode _buildDeptNode(Department dept, DepartmentTreeNode? old) {
    final node = DepartmentTreeNode(
      type: DepartmentTreeNodeType.department,
      id: dept.id,
      name: dept.name,
      campusId: dept.campusId,
      department: dept,
      expanded: old?.findByKey('department:${dept.id}')?.expanded ?? true,
    );
    for (final child in _departments.where((d) => d.id != dept.id && d.parentId == dept.id)) {
      node.children.add(_buildDeptNode(child, old));
    }
    return node;
  }

  // ---------------- 交互 ----------------

  /// 选中树节点：科室节点进入编辑态；医院/院区节点退出编辑与新增，
  /// 右侧回提示态。
  void selectNode(DepartmentTreeNode node) {
    _creating = false;
    _selectedNode = node.type == DepartmentTreeNodeType.department ? node : null;
    notifyListeners();
  }

  /// 进入新增模式：右侧表单清空，挂载目标为发起节点（医院根仅在
  /// 未设置院区时发起）。
  void startCreate(DepartmentTreeNode parent) {
    _createParent = parent;
    _creating = true;
    notifyListeners();
  }

  /// 取消新增，回到选中科室的编辑态（未选中则空态）。
  void cancelCreate() {
    _creating = false;
    notifyListeners();
  }

  /// 切换节点展开/折叠。
  void toggleExpand(DepartmentTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增科室到挂载目标下（目标类型决定 parentId/campusId 传参），
  /// 成功后整表重拉、选中新科室并退出新增模式。
  Future<bool> createDepartment({required String code, required String name, String? address, String? tel}) async {
    final hospId = _hospId;
    final parent = _createParent;
    if (hospId == null || hospId.isEmpty || parent == null) return false;
    final campusId = parent.type == DepartmentTreeNodeType.campus ? parent.id : null;
    final parentId = parent.type == DepartmentTreeNodeType.department ? parent.id : null;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _departmentService.create(
        hospId: hospId,
        code: code,
        name: name,
        campusId: campusId,
        parentId: parentId,
        address: address,
        tel: tel,
      );
      await _refreshTree();
      _selectedNode = _root?.findByKey('department:${created.id}');
      _creating = false;
      return true;
    } catch (e, st) {
      LogHelper.error('client:DepartmentManagementViewModel.createDepartment', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中科室（changes 键同后端契约：code/name/address/tel；
  /// 归属不可改），成功后整表重拉。
  Future<bool> updateDepartment(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _departmentService.update(id, changes);
      await _refreshTree();
      _selectedNode = _root?.findByKey('department:${updated.id}');
      return true;
    } catch (e, st) {
      LogHelper.error('client:DepartmentManagementViewModel.updateDepartment', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除科室，成功后整表重拉；删除选中科室时回退空态。
  Future<bool> deleteDepartment(DepartmentTreeNode node) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _departmentService.delete(node.id);
      await _refreshTree();
      return true;
    } catch (e, st) {
      LogHelper.error('client:DepartmentManagementViewModel.deleteDepartment', e, st);
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
