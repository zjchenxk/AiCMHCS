import 'package:client/main.dart';
import 'package:client/services/campus_service.dart';
import 'package:client/utils/log_helper.dart';
import 'package:common/model.dart';
import 'package:material_ui/material_ui.dart';

/// 右侧信息表单模式（同医院管理）。
enum CampusFormMode {
  /// 未选中任何院区（表单区显示提示）。
  empty,

  /// 编辑选中院区。
  edit,

  /// 新增模式（表单清空，归属为登录用户所属医院）。
  create,
}

/// 院区管理 ViewModel：院区归属当前登录用户的所属医院（hospId），全量
/// 拉取该医院的院区列表、右侧信息表单三态（编辑选中院区 / 新增）。
///
/// 增删成功后整表重拉并保持选中状态；同一医院且已加载时 loadData 直接
/// 跳过（切页保留状态），切换登录用户（医院变化）时强制重拉。
class CampusManagementViewModel extends ChangeNotifier {
  /// 构造函数：注入院区服务（缺省从服务定位器取，测试可覆写）。
  CampusManagementViewModel({CampusService? campusService}) : _campusService = campusService ?? getIt<CampusService>();

  final CampusService _campusService;

  final List<Campus> _campuses = [];
  String? _hospId;
  bool _loaded = false;
  Campus? _selectedCampus;
  bool _creating = false;
  bool _loading = false;
  bool _busy = false;
  String? _errorMsg;

  /// 当前院区列表（按创建顺序）。
  List<Campus> get campuses => _campuses;

  /// 当前选中院区（编辑态表单回填、列表高亮依据；新增模式下保留，
  /// 取消新增或选中新院区即回到其编辑态）。
  Campus? get selectedCampus => _selectedCampus;

  /// 右侧表单当前模式。
  CampusFormMode get formMode => _creating ? CampusFormMode.create : (_selectedCampus == null ? CampusFormMode.empty : CampusFormMode.edit);

  /// 首屏加载中。
  bool get loading => _loading;

  /// 增删改操作进行中（防重复提交）。
  bool get busy => _busy;

  String? get errorMsg => _errorMsg;

  /// 当前绑定的医院 ID（未加载为 null）。
  String? get hospId => _hospId;

  /// 登录用户未设置所属医院（页面据此显示引导提示而非空列表）。
  bool get unbound => _loaded && (_hospId == null || _hospId!.isEmpty);

  // ---------------- 加载 ----------------

  /// 加载登录用户所属医院的院区（进入页面时调用）。
  ///
  /// hospId 为空视为未绑定：清空列表并置提示；同一医院且已加载时跳过
  /// 重拉（切页保留状态），医院变化（切换登录用户）时强制重拉。
  Future<bool> loadData(String? hospId) async {
    final h = hospId?.trim() ?? '';
    if (_loaded && h == _hospId) return true;

    _hospId = h;
    if (h.isEmpty) {
      _loaded = true;
      _campuses.clear();
      _selectedCampus = null;
      _creating = false;
      _errorMsg = '当前登录用户未设置所属医院，无法管理院区';
      notifyListeners();
      return false;
    }

    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _refreshCampuses();
      _loaded = true;
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

  /// 拉取当前医院的全量院区并重建列表（选中院区被删时回退空态）。
  Future<void> _refreshCampuses() async {
    final campuses = await _campusService.getByHospital(_hospId!);
    _campuses
      ..clear()
      ..addAll(campuses);
    final selectedId = _selectedCampus?.id;
    if (selectedId != null) {
      _selectedCampus = _findById(selectedId);
    }
  }

  /// 在列表中按 ID 查找院区。
  Campus? _findById(String id) {
    for (final c in _campuses) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---------------- 交互 ----------------

  /// 选中院区（右侧切换为该院区的编辑表单，同时退出新增模式）。
  void selectCampus(Campus campus) {
    _creating = false;
    _selectedCampus = campus;
    notifyListeners();
  }

  /// 进入新增模式：右侧表单清空，归属为登录用户所属医院。
  void startCreate() {
    _creating = true;
    notifyListeners();
  }

  /// 取消新增，回到选中院区的编辑态（未选中则空态）。
  void cancelCreate() {
    _creating = false;
    notifyListeners();
  }

  // ---------------- 增删改 ----------------

  /// 新增院区到登录用户所属医院，成功后整表重拉、选中新院区并退出
  /// 新增模式。
  Future<bool> createCampus({
    required String code,
    required String name,
    String? address,
    String? tel,
  }) async {
    final hospId = _hospId;
    if (hospId == null || hospId.isEmpty) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final created = await _campusService.create(
        hospId: hospId,
        code: code,
        name: name,
        address: address,
        tel: tel,
      );
      await _refreshCampuses();
      _selectedCampus = _findById(created.id);
      _creating = false;
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

  /// 修改选中院区（changes 键同后端契约：code/name/address/tel；
  /// 归属医院不可改），成功后整表重拉。
  Future<bool> updateCampus(String id, Map<String, Object?> changes) async {
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final updated = await _campusService.update(id, changes);
      await _refreshCampuses();
      _selectedCampus = _findById(updated.id);
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

  /// 删除院区，成功后整表重拉；删除选中院区时回退空态。
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
