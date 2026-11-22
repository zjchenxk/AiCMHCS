// 照片管理 ViewModel 单元测试：Fake 服务构造注入，覆盖操作权限灰化
// （含权限加载失败全灰兜底）、当前儿童同步（幂等去重、切换清空重载、
// 未选定空操作）、拍照/上传保存透传缩略图并刷新列表、单选选中、按 ID
// 删除与下载在非 Web 平台的优雅失败路径。
import 'package:client/models/current_child.dart';
import 'package:client/services/child_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/utils/captured_photo.dart';
import 'package:client/view_models/child/photo_management_view_model.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版菜单服务：仅覆写操作权限查询。
class _FakeMenuService extends MenuService {
  _FakeMenuService({Set<String>? operationCodes}) : _operationCodes = operationCodes ?? const {};

  final Set<String> _operationCodes;

  @override
  Future<Set<String>> queryOperationCodes() async => {..._operationCodes};
}

/// 权限查询抛错的菜单服务（加载失败全灰兜底）。
class _FailingMenuService extends MenuService {
  @override
  Future<Set<String>> queryOperationCodes() async => throw Exception('权限加载失败');
}

/// 内存版儿童服务：模拟照片列表/保存/详情/删除。
class _FakeChildService extends ChildService {
  final Map<String, List<ChildPhoto>> photoStore = {};
  int nextId = 1;
  int photoListCalls = 0;
  int saveCalls = 0;
  int deleteCalls = 0;
  int photoDetailCalls = 0;
  bool failSave = false;
  bool failDelete = false;

  /// 最近一次保存入参（断言缩略图透传）。
  ({String childId, String photoBase64, String avatarBase64, String? thumbBase64})? lastSaveArgs;

  void saveDirect(String childId, {required String photo, required String avatar, String? thumb, required String createTime}) {
    photoStore
        .putIfAbsent(childId, () => [])
        .add(
          ChildPhoto(
            id: 'p${nextId++}',
            childId: childId,
            photoBase64: photo,
            avatarBase64: avatar,
            thumbBase64: thumb,
            creatorId: 'u1',
            creatorName: '张医生',
            hospId: 'h1',
            hospName: '示例人民医院',
            createTime: createTime,
          ),
        );
  }

  @override
  Future<List<ChildPhoto>> photos(String childId) async {
    photoListCalls++;
    final list = [...(photoStore[childId] ?? const <ChildPhoto>[])];
    // 与后端一致：按创建时间倒序，最新在前
    list.sort((a, b) => (b.createTime ?? '').compareTo(a.createTime ?? ''));
    return list;
  }

  @override
  Future<ChildPhoto> savePhoto({required String childId, required String photoBase64, required String avatarBase64, String? thumbBase64}) async {
    saveCalls++;
    if (failSave) throw Exception('保存失败');
    lastSaveArgs = (childId: childId, photoBase64: photoBase64, avatarBase64: avatarBase64, thumbBase64: thumbBase64);
    saveDirect(childId, photo: photoBase64, avatar: avatarBase64, thumb: thumbBase64, createTime: '2026-11-21 10:00:0$saveCalls');
    return photoStore[childId]!.last;
  }

  @override
  Future<ChildPhoto> photoDetail(String photoId) async {
    photoDetailCalls++;
    for (final list in photoStore.values) {
      for (final photo in list) {
        if (photo.id == photoId) return photo;
      }
    }
    throw Exception('照片不存在：$photoId');
  }

  @override
  Future<int> deletePhoto(String photoId) async {
    deleteCalls++;
    if (failDelete) throw Exception('删除失败');
    for (final list in photoStore.values) {
      final before = list.length;
      list.removeWhere((p) => p.id == photoId);
      if (list.length != before) return 1;
    }
    return 0;
  }
}

CurrentChild _child(String id) => CurrentChild(id: id, visitCardNo: 'V001', patientId: 'P001', name: '王小明', gender: '男', birthDate: DateTime(2026, 1, 1), phone: '');

CapturedPhoto _captured({String mark = 'A'}) => CapturedPhoto(photoBase64: 'PHOTO-$mark', avatarBase64: 'AVATAR-$mark', thumbBase64: 'THUMB-$mark');

void main() {
  // ---------------- 操作权限 ----------------

  test('loadPermissions：授权码齐备时四个 canXxx 全部放行', () async {
    final vm = PhotoManagementViewModel(
      childService: _FakeChildService(),
      menuService: _FakeMenuService(
        operationCodes: {
          PhotoManagementViewModel.opCapture,
          PhotoManagementViewModel.opUpload,
          PhotoManagementViewModel.opDownload,
          PhotoManagementViewModel.opDelete,
        },
      ),
    );
    expect(vm.canCapture, isFalse, reason: '加载前权限未知不放行');
    await vm.loadPermissions();
    expect(vm.canCapture, isTrue);
    expect(vm.canUpload, isTrue);
    expect(vm.canDownload, isTrue);
    expect(vm.canDelete, isTrue);
  });

  test('loadPermissions：无授权码与加载失败均全灰兜底', () async {
    final vm = PhotoManagementViewModel(childService: _FakeChildService(), menuService: _FakeMenuService());
    await vm.loadPermissions();
    expect(vm.canCapture, isFalse);
    expect(vm.canUpload, isFalse);
    expect(vm.canDownload, isFalse);
    expect(vm.canDelete, isFalse);

    final failing = PhotoManagementViewModel(childService: _FakeChildService(), menuService: _FailingMenuService());
    await failing.loadPermissions();
    expect(failing.canCapture, isFalse, reason: '权限未知不放行');
  });

  // ---------------- 当前儿童同步与列表装载 ----------------

  test('syncChild：未选定空操作、选定自动装载、同儿童幂等、切换重载', () async {
    final service = _FakeChildService();
    service.saveDirect('c1', photo: 'P1', avatar: 'A1', createTime: '2026-11-21 10:00:01');
    service.saveDirect('c2', photo: 'P2', avatar: 'A2', createTime: '2026-11-21 10:00:02');
    final vm = PhotoManagementViewModel(childService: service, menuService: _FakeMenuService());

    // 未选定：空操作不发请求
    await vm.syncChild(null);
    expect(vm.hasChild, isFalse);
    expect(vm.photos, isEmpty);
    expect(service.photoListCalls, 0);

    // 选定儿童 → 自动装载
    await vm.syncChild(_child('c1'));
    expect(vm.hasChild, isTrue);
    expect(vm.child!.name, '王小明');
    expect(vm.photos.map((p) => p.avatarBase64), ['A1']);
    expect(service.photoListCalls, 1);

    // 同一儿童重复同步：幂等不重拉
    await vm.syncChild(_child('c1'));
    expect(service.photoListCalls, 1);

    // 切换儿童：清空选中并重载
    vm.select('whatever');
    await vm.syncChild(_child('c2'));
    expect(vm.selectedId, isNull);
    expect(vm.photos.map((p) => p.avatarBase64), ['A2']);
    expect(service.photoListCalls, 2);

    // 切回未选定：清空
    await vm.syncChild(null);
    expect(vm.hasChild, isFalse);
    expect(vm.photos, isEmpty);
  });

  // ---------------- 保存（拍照/上传确定后） ----------------

  test('saveCaptured：无儿童拒绝；成功透传缩略图并刷新列表；失败置错误', () async {
    final service = _FakeChildService();
    final vm = PhotoManagementViewModel(childService: service, menuService: _FakeMenuService());

    // 无儿童：拒绝保存
    expect(await vm.saveCaptured(_captured()), isFalse);
    expect(service.saveCalls, 0);

    await vm.syncChild(_child('c1'));
    expect(await vm.saveCaptured(_captured(mark: 'B')), isTrue);
    expect(service.lastSaveArgs, isNotNull);
    expect(service.lastSaveArgs!.childId, 'c1');
    expect(service.lastSaveArgs!.photoBase64, 'PHOTO-B');
    expect(service.lastSaveArgs!.avatarBase64, 'AVATAR-B');
    expect(service.lastSaveArgs!.thumbBase64, 'THUMB-B', reason: '缩略图随保存透传');
    expect(vm.photos.map((p) => p.avatarBase64), ['AVATAR-B'], reason: '保存后列表自动刷新');
    expect(vm.selectedId, isNull);

    // 保存失败：置错误信息、返回 false
    service.failSave = true;
    expect(await vm.saveCaptured(_captured(mark: 'C')), isFalse);
    expect(vm.errorMsg, contains('保存失败'));
    vm.clearError();
    expect(vm.errorMsg, isNull);
  });

  // ---------------- 选中与删除 ----------------

  test('select 与 deleteSelected：选中定位、删除刷新并清选中、未选中拒绝', () async {
    final service = _FakeChildService();
    service.saveDirect('c1', photo: 'P1', avatar: 'A1', createTime: '2026-11-21 10:00:01');
    service.saveDirect('c1', photo: 'P2', avatar: 'A2', createTime: '2026-11-21 10:00:02');
    final vm = PhotoManagementViewModel(childService: service, menuService: _FakeMenuService());
    await vm.syncChild(_child('c1'));

    // 未选中：下载/删除均拒绝
    expect(await vm.deleteSelected(), isFalse);
    expect(service.deleteCalls, 0);

    // 选中最新一条（倒序首条）
    vm.select(vm.photos.first.id!);
    expect(vm.selectedPhoto!.avatarBase64, 'A2');

    // 再次点击同一张 → 取消选中
    vm.select(vm.photos.first.id!);
    expect(vm.selectedId, isNull);
    expect(vm.selectedPhoto, isNull);

    // 重新选中供删除
    vm.select(vm.photos.first.id!);
    expect(vm.selectedPhoto!.avatarBase64, 'A2');

    // 删除：刷新列表并清空选中
    expect(await vm.deleteSelected(), isTrue);
    expect(service.deleteCalls, 1);
    expect(vm.photos.map((p) => p.avatarBase64), ['A1']);
    expect(vm.selectedId, isNull);

    // 删除失败：置错误信息
    vm.select(vm.photos.first.id!);
    service.failDelete = true;
    expect(await vm.deleteSelected(), isFalse);
    expect(vm.errorMsg, contains('删除失败'));
  });

  // ---------------- 下载 ----------------

  test('downloadSelected：先取大图；非 Web 平台经另存桩优雅失败', () async {
    final service = _FakeChildService();
    // 照片内容须为合法 base64（下载链路会真实解码）
    service.saveDirect('c1', photo: 'UGhvdG8x', avatar: 'A1', thumb: 'T1', createTime: '2026-11-21 10:00:01');
    final vm = PhotoManagementViewModel(childService: service, menuService: _FakeMenuService());

    // 未选中：拒绝
    await vm.syncChild(_child('c1'));
    expect(await vm.downloadSelected(), isFalse);
    expect(service.photoDetailCalls, 0);

    // 选中后下载：VM 先按需取详情，再经 web_download 桩触发（VM 测试
    // 运行于非 Web 平台，另存抛 UnsupportedError，被 VM 捕获置错误信息）
    vm.select(vm.photos.first.id!);
    expect(await vm.downloadSelected(), isFalse);
    expect(service.photoDetailCalls, 1);
    expect(vm.errorMsg, contains('仅支持 Web 平台'));
  });
}
