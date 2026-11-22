import 'dart:convert';

import 'package:client/main.dart';
import 'package:client/models/current_child.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/captured_photo.dart';
import 'package:client/utils/log_helper.dart';
import 'package:client/utils/web_download.dart';
import 'package:common/model.dart';
import 'package:flutter/foundation.dart';

/// 儿童照片管理视图模型：操作权限（按钮灰化）、当前儿童上下文（主界面
/// 顶部搜索选定后同步）、该儿童的拍照历史列表（CHILD_PHOTO，倒序最新
/// 在前）、单选选中态与拍照/上传/下载/删除流转。
///
/// 数据流：照片管理页监听主界面「当前儿童」变化经 [syncChild] 同步，
/// 儿童变化时清空选中并自动重载列表；拍照/上传对话框确定后由页面调
/// [saveCaptured] 立即入库并刷新列表；下载按需取大图（列表仅带头像/
/// 缩略图），经 Web 另存落地本地。
class PhotoManagementViewModel extends ChangeNotifier {
  /// 构造函数：可选注入服务（缺省经服务定位器取，便于测试覆写）。
  PhotoManagementViewModel({ChildService? childService, MenuService? menuService}) : _childService = childService ?? getIt<ChildService>(), _menuService = menuService ?? getIt<MenuService>();

  final ChildService _childService;

  final MenuService _menuService;

  // ---------------- 操作权限（SYS_MENU 操作项 ITEM_CODE） ----------------

  /// 拍照操作权限码。
  static const String opCapture = '0202000001';

  /// 上传操作权限码。
  static const String opUpload = '0202000002';

  /// 下载操作权限码。
  static const String opDownload = '0202000003';

  /// 删除操作权限码。
  static const String opDelete = '0202000004';

  /// 当前角色已授权的操作权限码集合（未加载/失败时为空集，按钮全灰化——
  /// 权限未知不放行）。
  final Set<String> _operationCodes = {};

  /// 是否拥有拍照操作权限。
  bool get canCapture => _operationCodes.contains(opCapture);

  /// 是否拥有上传操作权限。
  bool get canUpload => _operationCodes.contains(opUpload);

  /// 是否拥有下载操作权限。
  bool get canDownload => _operationCodes.contains(opDownload);

  /// 是否拥有删除操作权限。
  bool get canDelete => _operationCodes.contains(opDelete);

  /// 拉取当前角色操作权限码（进页时调用）。
  Future<void> loadPermissions() async {
    try {
      final codes = await _menuService.queryOperationCodes();
      _operationCodes
        ..clear()
        ..addAll(codes);
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.loadPermissions', e, st);
      _operationCodes.clear();
    }
    notifyListeners();
  }

  // ---------------- 当前儿童与列表状态 ----------------

  CurrentChild? _child;

  /// 当前儿童（主界面顶部搜索选定；null 表示未选儿童）。
  CurrentChild? get child => _child;

  /// 是否已选定儿童。
  bool get hasChild => _child != null && _child!.id.isNotEmpty;

  List<ChildPhoto> _photos = [];

  /// 当前儿童的拍照记录列表（倒序最新在前）。
  List<ChildPhoto> get photos => List.unmodifiable(_photos);

  /// 列表是否为空（已选定儿童但无拍照记录）。
  bool get isEmpty => _photos.isEmpty;

  String? _selectedId;

  /// 当前选中的照片 ID（单击选中，供下载/删除）。
  String? get selectedId => _selectedId;

  /// 当前选中的照片记录（未选中为 null）。
  ChildPhoto? get selectedPhoto {
    for (final photo in _photos) {
      if (photo.id == _selectedId) return photo;
    }
    return null;
  }

  /// 选中/取消选中照片（单击选中，再次点击同一张即取消选择，供下载/
  /// 删除取用）。
  void select(String photoId) {
    _selectedId = _selectedId == photoId ? null : photoId;
    notifyListeners();
  }

  bool _loading = false;

  /// 列表装载中。
  bool get loading => _loading;

  bool _busy = false;

  /// 保存/下载/删除等操作进行中（按钮灰化防重复提交）。
  bool get busy => _busy;

  String? _errorMsg;

  /// 最近一次操作的错误信息（页面监听后以 SnackBar 提示并 [clearError]）。
  String? get errorMsg => _errorMsg;

  /// 清空错误信息（SnackBar 关闭按钮回调）。
  void clearError() {
    _errorMsg = null;
  }

  String _messageOf(Object e) => e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');

  /// 同步主界面「当前儿童」上下文：儿童变化时清空选中与列表并自动重载
  /// （同一儿童重复同步为幂等空操作）。
  Future<void> syncChild(CurrentChild? child) async {
    final newId = child?.id ?? '';
    final oldId = _child?.id ?? '';
    if (newId == oldId) return;
    _child = newId.isEmpty ? null : child;
    _selectedId = null;
    _photos = [];
    _errorMsg = null;
    notifyListeners();
    if (hasChild) {
      await loadPhotos();
    }
  }

  /// 装载当前儿童的照片列表（儿童未选定时空操作）。
  Future<void> loadPhotos() async {
    if (!hasChild) return;
    _loading = true;
    _errorMsg = null;
    notifyListeners();
    try {
      _photos = await _childService.photos(_child!.id);
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.loadPhotos', e, st);
      _errorMsg = _messageOf(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 拍照/上传对话框确定后保存：为当前儿童追加一条拍照记录并刷新列表
  /// （children: 调用方已在对话框拿到 CapturedPhoto；无儿童时拒绝）。
  ///returns: true 表示保存成功
  Future<bool> saveCaptured(CapturedPhoto photo) async {
    if (!hasChild) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _childService.savePhoto(
        childId: _child!.id,
        photoBase64: photo.photoBase64,
        avatarBase64: photo.avatarBase64,
        thumbBase64: photo.thumbBase64,
      );
      _selectedId = null;
      await loadPhotos();
      return true;
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.saveCaptured', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 装载单条照片详情（放大预览用，按需取大图；不改动列表状态）。
  ///returns: 详情（失败时置 [errorMsg] 并返回 null）
  Future<ChildPhoto?> loadDetail(String photoId) async {
    try {
      return await _childService.photoDetail(photoId);
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.loadDetail', e, st);
      _errorMsg = _messageOf(e);
      notifyListeners();
      return null;
    }
  }

  /// 下载选中的照片：按需取大图（列表仅带缩略图），以
  /// 「儿童姓名_拍摄时间.jpg」经 Web 另存落地本地。
  ///returns: true 表示已触发下载
  Future<bool> downloadSelected() async {
    final photo = selectedPhoto;
    if (photo == null || photo.id == null || !hasChild) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      final detail = await _childService.photoDetail(photo.id!);
      final bytes = base64Decode(detail.photoBase64 ?? '');
      if (bytes.isEmpty) {
        throw Exception('照片内容为空，无法下载');
      }
      // 文件名仅保留数字时间戳部分（'YYYY-MM-DD HH:MM:SS' →
      // 'YYYYMMDDHHMMSS'），避免文件名非法字符。
      final timePart = (detail.createTime ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final name = _child!.name.isNotEmpty ? _child!.name : '儿童照片';
      await saveBytes(bytes, '${name}_$timePart.jpg');
      return true;
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.downloadSelected', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 删除选中的照片（调用方负责删除确认对话框），删除后刷新列表并清空
  /// 选中。
  ///returns: true 表示删除成功
  Future<bool> deleteSelected() async {
    final photo = selectedPhoto;
    if (photo == null || photo.id == null || !hasChild) return false;
    _busy = true;
    _errorMsg = null;
    notifyListeners();
    try {
      await _childService.deletePhoto(photo.id!);
      _selectedId = null;
      await loadPhotos();
      return true;
    } catch (e, st) {
      LogHelper.error('client:PhotoManagementViewModel.deleteSelected', e, st);
      _errorMsg = _messageOf(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
