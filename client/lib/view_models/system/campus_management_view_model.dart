import 'package:client/main.dart';
import 'package:client/models/hospital_tree_node.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 院区管理 ViewModel：左侧医院树全量加载（一次取扁平列表本地建树）、
/// 院区全量拉取后按医院分组，右侧展示选中医院的院区列表。
///
/// 增删成功后院区整表重拉（院区规模有限，整表重拉最简单且保证本地与
/// 后端一致）；医院树仅作选择载体，不做增删（走医院设置页）。
class CampusManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入医院与院区服务（缺省从服务定位器取，测试可覆写）。
  CampusManagementViewModel({
    HospitalService? hospitalService,
    CampusService? campusService,
  }) : _hospitalService = hospitalService ?? getIt<HospitalService>(),
       _campusService = campusService ?? getIt<CampusService>();

  final HospitalService _hospitalService;
  final CampusService _campusService;

  final List<HospitalTreeNode> _hospitalTree = [];
  final Map<String, List<Campus>> _campusesByHosp = {};
  HospitalTreeNode? _selectedNode;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 医院树（顶级医院列表，子级挂在各节点 children 下）。
  List<HospitalTreeNode> get hospitalTree => _hospitalTree;

  /// 当前选中医院节点（右侧院区列表数据源、树上高亮依据）。
  HospitalTreeNode? get selectedNode => _selectedNode;

  /// 选中医院的院区列表（未选中医院为空）。
  List<Campus> get campuses => _selectedNode == null ? const [] : (_campusesByHosp[_selectedNode!.id] ?? const []);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  // ---------------- 加载 ----------------

  /// 加载医院树与全部院区（进入页面时调用），默认选中首个顶级医院。
  Future<bool> loadData() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _loadHospitals();
      await _refreshCampuses();
      if (_selectedNode == null && _hospitalTree.isNotEmpty) {
        _selectedNode = _hospitalTree.first;
      }
      return true;
    } catch (e, st) {
      LogHelper.error('client:CampusManagementViewModel.loadData', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取全量医院并重建本地树（保持旧树展开与选中状态）。
  Future<void> _loadHospitals() async {
    final hospitals = await _hospitalService.getAll();

    // 记录旧树状态（展开标记、选中）
    final oldExpanded = <String, bool>{};
    void collect(List<HospitalTreeNode> nodes) {
      for (final n in nodes) {
        oldExpanded[n.id] = n.expanded;
        collect(n.children);
      }
    }

    collect(_hospitalTree);
    final oldSelectedId = _selectedNode?.id;

    final nodes = <String, HospitalTreeNode>{
      for (final h in hospitals)
        h.id: HospitalTreeNode(
          id: h.id,
          name: h.name,
          parentId: h.parentId,
          expanded: oldExpanded[h.id] ?? true,
        ),
    };

    final roots = <HospitalTreeNode>[];
    for (final h in hospitals) {
      final node = nodes[h.id]!;
      final parent = h.parentId == null ? null : nodes[h.parentId];
      if (parent != null) {
        parent.children.add(node);
      } else {
        // 上级缺失（含 null）按顶级处理，孤儿节点不至丢失
        roots.add(node);
      }
    }
    _hospitalTree
      ..clear()
      ..addAll(roots);

    // 选中保持：被删则清空
    _selectedNode = oldSelectedId == null ? null : nodes[oldSelectedId];
  }

  /// 拉取全量院区并按医院分组。
  Future<void> _refreshCampuses() async {
    final campuses = await _campusService.getAll();
    final map = <String, List<Campus>>{};
    for (final c in campuses) {
      map.putIfAbsent(c.hospId, () => []).add(c);
    }
    _campusesByHosp
      ..clear()
      ..addAll(map);
  }

  // ---------------- 交互 ----------------

  /// 选中医院（右侧切换为该医院的院区列表）。
  void selectNode(HospitalTreeNode node) {
    _selectedNode = node;
    notifyListeners();
  }

  /// 展开/折叠节点（树为全量加载，仅翻转标记）。
  void toggleExpand(HospitalTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增院区到当前选中医院，成功后整表重拉。
  Future<bool> createCampus({
    required String code,
    required String name,
    String? address,
    String? tel,
  }) async {
    final target = _selectedNode;
    if (target == null) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _campusService.create(
        hospId: target.id,
        code: code,
        name: name,
        address: address,
        tel: tel,
      );
      await _refreshCampuses();
      return true;
    } catch (e, st) {
      LogHelper.error('client:CampusManagementViewModel.createCampus', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改院区（changes 键同后端契约：code/name/address/tel），成功后整表重拉。
  Future<bool> updateCampus(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _campusService.update(id, changes);
      await _refreshCampuses();
      return true;
    } catch (e, st) {
      LogHelper.error('client:CampusManagementViewModel.updateCampus', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除院区，成功后整表重拉。
  Future<bool> deleteCampus(Campus campus) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _campusService.delete(campus.id);
      await _refreshCampuses();
      return true;
    } catch (e, st) {
      LogHelper.error('client:CampusManagementViewModel.deleteCampus', e, st);
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
