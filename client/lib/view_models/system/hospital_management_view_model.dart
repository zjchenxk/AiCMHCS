import 'package:client/main.dart';
import 'package:client/models/hospital_info.dart';
import 'package:client/models/hospital_tree_node.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 图片尺寸限制常量
class OrganImageLimit {
  static const int logoMaxSize = 200; // Logo 最大分辨率 200x200
  static const int sealMaxSize = 300; // 印章最大分辨率 300x300
}

class HospitalManagementViewModel extends ChangeNotifier {
  final Map<String, HospitalInfo> _organInfoMap = {};
  final List<HospitalTreeNode> _organTree = [];
  HospitalTreeNode? _selectedNode;

  List<HospitalTreeNode> get organTree => _organTree;
  HospitalTreeNode? get selectedNode => _selectedNode;

  List<Province>? _provinces;
  List<City>? _cities;
  List<County>? _counties;
  List<Town>? _towns;

  List<Province>? get provinces => _provinces;
  List<City>? get cities => _cities;
  List<County>? get counties => _counties;
  List<Town>? get towns => _towns;

  Province? _selectedProvince;
  City? _selectedCity;
  County? _selectedCounty;
  Town? _selectedTown;

  Province? get selectedProvince => _selectedProvince;
  City? get selectedCity => _selectedCity;
  County? get selectedCounty => _selectedCounty;
  Town? get selectedTown => _selectedTown;

  bool _loading = false;
  String? _errorMsg;

  bool get loading => _loading;
  String? get errorMsg => _errorMsg;

  bool _addressLoading = false;
  bool get addressLoading => _addressLoading;

  /// 当前所选医院的信息
  HospitalInfo? get selectedOrganInfo => _selectedNode == null ? null : _organInfoMap[_selectedNode!.id];

  /// 加载医院树（实际项目替换为接口请求）
  Future<void> loadOrganTree() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();

    try {
      // TODO: 替换为后端接口，如 http.get('/api/hospital/tree')
      await Future.delayed(const Duration(milliseconds: 300));
      _buildMockTree();
      // 默认选中第一个根节点
      if (_organTree.isNotEmpty) {
        selectOrgan(_organTree.first.id);
      }
    } catch (e) {
      _errorMsg = '加载医院列表失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _buildMockTree() {
    _organTree.clear();
    _organInfoMap.clear();

    final root = HospitalTreeNode(id: 'H001', name: '示例人民医院');
    final child1 = HospitalTreeNode(id: 'H001-01', name: '示例人民医院-第一分院', parentId: root.id);
    final child2 = HospitalTreeNode(id: 'H001-02', name: '示例人民医院-第二分院', parentId: root.id);
    final grandChild = HospitalTreeNode(id: 'H001-01-01', name: '第一分院-社区门诊', parentId: child1.id);
    child1.children.add(grandChild);
    root.children.addAll([child1, child2]);

    final root2 = HospitalTreeNode(id: 'H002', name: '示例中医院');
    _organTree.addAll([root, root2]);

    for (final node in _organTree) {
      _initInfoRecursive(node);
    }
  }

  void _initInfoRecursive(HospitalTreeNode node) {
    if (!_organInfoMap.containsKey(node.id)) {
      // TODO: 从接口加载各医院已有配置信息
      _organInfoMap[node.id] = HospitalInfo(id: node.id, name: node.name);
    }
    for (final c in node.children) {
      _initInfoRecursive(c);
    }
  }

  /// 选中某个医院
  void selectOrgan(String id) {
    _selectedNode = _findNode(id);
    notifyListeners();
  }

  HospitalTreeNode? _findNode(String id) {
    for (final node in _organTree) {
      final r = node.find(id);
      if (r != null) return r;
    }
    return null;
  }

  /// 展开/折叠节点
  void toggleExpand(HospitalTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  /// 添加下级医院
  Future<bool> addChildOrgan(HospitalTreeNode parent, String name) async {
    if (name.trim().isEmpty) return false;
    final child = HospitalTreeNode(
      id: '${parent.id}-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      parentId: parent.id,
    );
    parent.children.add(child);
    _organInfoMap[child.id] = HospitalInfo(id: child.id, name: child.name);
    parent.expanded = true;
    notifyListeners();
    return true;
  }

  /// 删除医院（有下级时禁止删除）
  Future<bool> removeOrgan(HospitalTreeNode node) async {
    if (node.children.isNotEmpty) {
      _errorMsg = '该医院存在下级医院，不能删除';
      notifyListeners();
      return false;
    }
    void remove(List<HospitalTreeNode> list) {
      list.removeWhere((n) => n.id == node.id);
      for (final n in list) {
        remove(n.children);
      }
    }

    remove(_organTree);
    _organInfoMap.remove(node.id);
    if (_selectedNode?.id == node.id) {
      _selectedNode = null;
    }
    notifyListeners();
    return true;
  }

  /// 清空行政区划选择（切换医院时调用）
  void clearAdminDivisions() {
    _selectedProvince = null;
    _selectedCity = null;
    _selectedCounty = null;
    _selectedTown = null;
    _cities = null;
    _counties = null;
    _towns = null;
    notifyListeners();
  }

  /// 获取省/自治区/直辖市列表
  /// 返回值: true表示获取成功，false表示获取失败
  Future<bool> getProvinces() async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      final AdminDivisionsService service = getIt<AdminDivisionsService>();
      _provinces = await service.getProvinces() ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _addressLoading = false;
      _errorMsg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      notifyListeners();

      return false;
    }
  }

  /// 选择省/自治区/直辖市后加载市/州列表
  Future<bool> selectProvince(Province? p) async {
    _selectedProvince = p;
    _selectedCity = null;
    _selectedCounty = null;
    _selectedTown = null;
    _cities = null;
    _counties = null;
    _towns = null;
    notifyListeners();

    if (p == null) return true;

    return getCitiesByProvince(p.code);
  }

  /// 获取指定省/自治区/直辖市的市/州列表
  /// 返回值: true表示获取成功，false表示获取失败
  Future<bool> getCitiesByProvince(String provinceCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      final AdminDivisionsService service = getIt<AdminDivisionsService>();
      _cities = await service.getCitiesByProvince(provinceCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _addressLoading = false;
      _errorMsg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      notifyListeners();

      return false;
    }
  }

  /// 选择市/州后加载县/区/旗列表
  Future<bool> selectCity(City? c) async {
    _selectedCity = c;
    _selectedCounty = null;
    _selectedTown = null;
    _counties = null;
    _towns = null;
    notifyListeners();

    if (c == null) return true;

    return getCountiesByCity(c.code);
  }

  /// 获取指定市/州的县/区/旗列表
  /// 返回值: true表示获取成功，false表示获取失败
  Future<bool> getCountiesByCity(String cityCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      final AdminDivisionsService service = getIt<AdminDivisionsService>();
      _counties = await service.getCountiesByCity(cityCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _addressLoading = false;
      _errorMsg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      notifyListeners();

      return false;
    }
  }

  /// 选择县/区/旗后加载乡镇/街道列表
  Future<bool> selectCounty(County? c) async {
    _selectedCounty = c;
    _selectedTown = null;
    _towns = null;
    notifyListeners();

    if (c == null) return true;

    return getTownsByCounty(c.code);
  }

  /// 获取指定县/区/旗的乡镇/街道列表
  /// 返回值: true表示获取成功，false表示获取失败
  Future<bool> getTownsByCounty(String countyCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      final AdminDivisionsService service = getIt<AdminDivisionsService>();
      _towns = await service.getTownsByCounty(countyCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _addressLoading = false;
      _errorMsg = e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
      notifyListeners();

      return false;
    }
  }

  /// 选择乡镇/街道
  void selectTown(Town? t) {
    _selectedTown = t;
    notifyListeners();
  }

  /// 保存医院信息（实际项目替换为接口请求）
  Future<bool> saveOrganInfo(HospitalInfo info) async {
    _errorMsg = null;
    if (info.orgCode.trim().isEmpty) {
      _errorMsg = '组织机构代码不能为空';
      notifyListeners();
      return false;
    }
    if (info.name.trim().isEmpty) {
      _errorMsg = '医院中文名称不能为空';
      notifyListeners();
      return false;
    }
    if (info.phone.trim().isEmpty) {
      _errorMsg = '联系电话不能为空';
      notifyListeners();
      return false;
    }

    _loading = true;
    notifyListeners();
    try {
      // TODO: 替换为后端接口，如 http.post('/api/hospital/save', info.toJson())
      await Future.delayed(const Duration(milliseconds: 300));
      _organInfoMap[info.id] = info;
      return true;
    } catch (e) {
      _errorMsg = '保存失败：$e';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
