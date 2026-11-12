import 'package:client/main.dart';
import 'package:client/models/hospital_info.dart';
import 'package:client/models/hospital_tree_node.dart';
import 'package:client/services/admin_divisions_service.dart';
import 'package:client/services/hospital_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 图片尺寸限制常量
class OrganImageLimit {
  static const int logoMaxSize = 200; // Logo 最大分辨率 200x200
  static const int sealMaxSize = 300; // 印章最大分辨率 300x300

  /// 报告单水印最大分辨率（宽x高）410x580：宽高比与 A4/A5 纵向
  /// （210x297 / 148x210mm）一致（1:√2），同一水印图缩放后可用于两种
  /// 报告单。
  static const int watermarkMaxWidth = 410;
  static const int watermarkMaxHeight = 580;
}

/// 右侧信息表单模式。
enum HospitalFormMode {
  /// 未选中任何节点（表单区显示提示）。
  empty,

  /// 编辑选中医院（基本信息可改、上级只读）。
  edit,

  /// 新增模式（表单清空，上级医院显示新增目标父级，只读）。
  create,
}

/// 医院管理 ViewModel：左树全量加载（医院规模有限，一次取扁平列表本地
/// 建树）、右侧信息表单三态（编辑选中医院 / 新增顶级或下级）、级联删除。
///
/// 增删成功后整表重拉并保持展开/选中状态（与行政区划的懒加载+本地同步
/// 不同：医院表百级以内，整表重拉最简单且保证本地树与后端一致）；
/// 修改无结构变化，本地同步即可。
class HospitalManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入医院与行政区划服务（缺省从服务定位器取，测试可覆写）。
  HospitalManagementViewModel({
    HospitalService? hospitalService,
    AdminDivisionsService? divisionsService,
  }) : _hospitalService = hospitalService ?? getIt<HospitalService>(),
       _divisionsService = divisionsService ?? getIt<AdminDivisionsService>();

  final HospitalService _hospitalService;
  final AdminDivisionsService _divisionsService;

  final List<HospitalTreeNode> _hospitalTree = [];
  final Map<String, HospitalInfo> _infoMap = {};
  HospitalTreeNode? _selectedNode;
  HospitalTreeNode? _creatingParentNode;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 数据范围根医院 ID（服务端按登录用户所属医院过滤下发；null 表示
  /// 未限定，如系统管理员全量视图）。
  String? _scopeRootId;

  /// 医院树（顶级医院列表，子级挂在各节点 children 下）。
  List<HospitalTreeNode> get hospitalTree => _hospitalTree;

  /// 数据范围根医院 ID：非空时树仅含该医院及其嵌套下级（列表接口随
  /// 登录用户 hospId 下发，用于隐藏「添加顶级医院」等越界入口）。
  String? get scopeRootId => _scopeRootId;

  /// 当前选中节点（编辑模式数据源、树上高亮依据；新增模式下保留，
  /// 取消新增或选中新节点即回到其编辑态）。
  HospitalTreeNode? get selectedNode => _selectedNode;

  /// 新增模式的目标父节点（null 表示新增顶级医院）。
  HospitalTreeNode? get creatingParentNode => _creatingParentNode;

  /// 右侧表单当前模式。
  HospitalFormMode get formMode => _creating ? HospitalFormMode.create : (_selectedNode == null ? HospitalFormMode.empty : HospitalFormMode.edit);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 当前所选医院的信息（编辑态表单回填）。
  HospitalInfo? get selectedHospitalInfo => _selectedNode == null ? null : _infoMap[_selectedNode!.id];

  // ---------------- 医院树：加载与状态 ----------------

  /// 加载全部医院并重建树（进入页面时调用）。
  Future<bool> loadHospitals() async {
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _fetchAndRebuild();
      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.loadHospitals', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拉取全量医院并重建本地树（不切首屏 loading 标记，供增删后刷新）。
  Future<void> _fetchAndRebuild() async {
    final (hospitals, scopeRootId) = await _hospitalService.getAll();
    _scopeRootId = scopeRootId;
    _rebuildTree(hospitals);
  }

  /// 用扁平列表重建树：保持旧树的展开状态与选中（新节点默认展开），
  /// 选中/新增目标父级被删时回退状态。
  void _rebuildTree(List<Hospital> hospitals) {
    // 记录旧树状态（展开标记、选中、新增目标父级）
    final oldExpanded = <String, bool>{};
    void collect(List<HospitalTreeNode> nodes) {
      for (final n in nodes) {
        oldExpanded[n.id] = n.expanded;
        collect(n.children);
      }
    }

    collect(_hospitalTree);
    final oldSelectedId = _selectedNode?.id;
    final oldCreatingParentId = _creatingParentNode?.id;

    final nodes = <String, HospitalTreeNode>{
      for (final h in hospitals)
        h.id: HospitalTreeNode(
          id: h.id,
          name: h.name,
          parentId: h.parentId,
          expanded: oldExpanded[h.id] ?? true,
        ),
    };
    _infoMap
      ..clear()
      ..addEntries(hospitals.map((h) => MapEntry(h.id, HospitalInfo.fromHospital(h))));

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

    // 选中保持：被删则清空；新增目标父级被删则退出新增模式
    _selectedNode = oldSelectedId == null ? null : nodes[oldSelectedId];
    _creatingParentNode = oldCreatingParentId == null ? null : nodes[oldCreatingParentId];
    if (_creating && oldCreatingParentId != null && _creatingParentNode == null) {
      _creating = false;
      _creatingParentNode = null;
    }
  }

  /// 选中医院（右侧切换为该医院的编辑表单，同时退出新增模式）。
  void selectNode(HospitalTreeNode node) {
    _creating = false;
    _selectedNode = node;
    notifyListeners();
  }

  /// 进入新增模式：右侧表单清空，上级医院显示 parent（空为顶级医院）。
  void startCreate({HospitalTreeNode? parent}) {
    _creating = true;
    _creatingParentNode = parent;
    notifyListeners();
  }

  /// 取消新增，回到选中医院的编辑态（未选中则空态）。
  void cancelCreate() {
    _creating = false;
    notifyListeners();
  }

  /// 展开/折叠节点（树为全量加载，仅翻转标记）。
  void toggleExpand(HospitalTreeNode node) {
    node.expanded = !node.expanded;
    notifyListeners();
  }

  /// 新增医院（表单提交调用，parentId 由表单按新增目标父级写入 info），
  /// 成功后整表重拉、选中新医院并退出新增模式。
  Future<bool> createHospital(HospitalInfo info) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _hospitalService.create(
        parentId: info.parentId,
        code: info.code ?? '',
        name: info.name,
        nameEn: info.nameEn,
        province: info.province,
        city: info.city,
        county: info.county,
        town: info.town,
        address: info.address,
        tel: info.tel,
        logoBase64: info.logoImage,
        sealBase64: info.sealImage,
        watermarkBase64: info.watermarkImage,
      );
      await _fetchAndRebuild();
      _selectedNode = _findNode(created.id);
      _creating = false;
      _creatingParentNode = null;
      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.createHospital', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 修改选中医院（无结构变化，本地同步树节点名称与信息即可）。
  Future<bool> updateHospital(HospitalInfo info) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _hospitalService.update(info.id, info.toChanges());
      final node = _findNode(updated.id);
      if (node != null) node.name = updated.name;
      _infoMap[updated.id] = HospitalInfo.fromHospital(updated);
      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.updateHospital', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 查询子树规模（含自身）与子树内院区数，删除确认提示用。
  Future<(int, int)> subtreeInfo(HospitalTreeNode node) async {
    final (_, subtree, campus) = await _hospitalService.getDetail(node.id);
    return (subtree, campus);
  }

  /// 级联删除医院及其全部下级，成功后整表重拉重建树。
  Future<bool> deleteHospital(HospitalTreeNode node) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _hospitalService.delete(node.id);
      await _fetchAndRebuild();
      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.deleteHospital', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 在树中按 ID 查找节点。
  HospitalTreeNode? _findNode(String id) {
    for (final node in _hospitalTree) {
      final r = node.find(id);
      if (r != null) return r;
    }
    return null;
  }

  // ---------------- 地址级联（医院信息表单用） ----------------

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

  bool _addressLoading = false;
  bool get addressLoading => _addressLoading;

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

      _provinces = await _divisionsService.getProvinces() ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.getProvinces', e, st);
      _addressLoading = false;
      _errorMsg = _messageOf(e);
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

  /// 获取指定省/自治州/直辖市的市/州列表
  Future<bool> getCitiesByProvince(String provinceCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      _cities = await _divisionsService.getCitiesByProvince(provinceCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.getCitiesByProvince', e, st);
      _addressLoading = false;
      _errorMsg = _messageOf(e);
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
  Future<bool> getCountiesByCity(String cityCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      _counties = await _divisionsService.getCountiesByCity(cityCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.getCountiesByCity', e, st);
      _addressLoading = false;
      _errorMsg = _messageOf(e);
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
  Future<bool> getTownsByCounty(String countyCode) async {
    try {
      _addressLoading = true;
      _errorMsg = null;
      notifyListeners();

      _towns = await _divisionsService.getTownsByCounty(countyCode) ?? [];

      _addressLoading = false;
      notifyListeners();

      return true;
    } catch (e, st) {
      LogHelper.error('client:HospitalManagementViewModel.getTownsByCounty', e, st);
      _addressLoading = false;
      _errorMsg = _messageOf(e);
      notifyListeners();

      return false;
    }
  }

  /// 选择乡镇/街道
  void selectTown(Town? t) {
    _selectedTown = t;
    notifyListeners();
  }

  // ---------------- 通用 ----------------

  /// 剥离异常前缀（Exception(: ...)），取用户可读信息。
  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  void clearError() {
    _errorMsg = null;
    notifyListeners();
  }
}
