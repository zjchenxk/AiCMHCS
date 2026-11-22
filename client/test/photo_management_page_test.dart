// 照片管理页 widget 测试：Fake 服务构造注入 + Provider.value 包裹真实
// MainViewModel，覆盖未选儿童空态与按钮灰化、权限缺失全灰、照片卡片
// 渲染（缩略图/相对时间/创建人）、单击选中高亮与删除确认对话框流程
// （确认后按 ID 删除并刷新）。
import 'dart:convert';

import 'package:client/main.dart' as app;
import 'package:client/services/child_service.dart';
import 'package:client/services/menu_service.dart';
import 'package:client/services/time_service.dart';
import 'package:client/view_models/child/photo_management_view_model.dart';
import 'package:client/view_models/main/main_view_model.dart';
import 'package:client/views/child/photo_management_page.dart';
import 'package:common/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 内存版菜单服务：仅覆写操作权限查询。
class _FakeMenuService extends MenuService {
  _FakeMenuService({Set<String>? operationCodes}) : _operationCodes = operationCodes ?? const {};

  final Set<String> _operationCodes;

  @override
  Future<Set<String>> queryOperationCodes() async => {..._operationCodes};
}

/// 内存版儿童服务：整档装载/最近照片（侧边栏用）+ 照片列表/删除。
class _FakeChildService extends ChildService {
  _FakeChildService(this.child);

  final ChildInfo child;
  final Map<String, List<ChildPhoto>> photoStore = {};
  int nextId = 1;
  int deleteCalls = 0;

  void saveDirect(String childId, {required String avatar, required String thumb, required String createTime}) {
    photoStore
        .putIfAbsent(childId, () => [])
        .add(
          ChildPhoto(
            id: 'p${nextId++}',
            childId: childId,
            photoBase64: base64Encode(utf8.encode('photo')),
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
  Future<ChildArchive> load(String id) async => (child, null, const <ChildGuardianInfo>[]);

  @override
  Future<ChildPhoto?> latestPhoto(String childId) async => null;

  @override
  Future<List<ChildPhoto>> photos(String childId) async {
    final list = [...(photoStore[childId] ?? const <ChildPhoto>[])];
    list.sort((a, b) => (b.createTime ?? '').compareTo(a.createTime ?? ''));
    return list;
  }

  @override
  Future<ChildPhoto> photoDetail(String photoId) async {
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
    for (final list in photoStore.values) {
      final before = list.length;
      list.removeWhere((p) => p.id == photoId);
      if (list.length != before) return 1;
    }
    return 0;
  }
}

/// 测试用儿童基础档案。
ChildInfo buildChildInfo() => ChildInfo(
  id: 'child-1',
  checkTime: '2026-11-17',
  name: '测试儿童',
  sex: '1',
  birthDate: '2023-09-01',
  addressProvince: '330000',
  addressCity: '330100',
  addressCounty: '330106',
  addressDetails: '测试路 1 号',
  creatorId: 'user-1',
  creatorName: '测试医生',
  hospId: 'hosp-1',
  hospName: '测试医院',
);

/// 有效 720×900 JPEG（1×1 像素灰图，够 Image.memory 解码成功渲染）。
final _jpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a'
  'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAA'
  'AAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q==',
);

const _testLoginUser = LoginUser(id: '1', userCode: 'doctor01', userName: '王心怡', roleId: '', userType: 'DOCTOR', hospId: '1');

void main() {
  setUp(() {
    // 页面相对时间标签依赖全局时间服务（未校准即本地时钟）
    if (!app.getIt.isRegistered<TimeService>()) {
      app.getIt.registerLazySingleton<TimeService>(() => TimeService());
    }
  });

  Widget wrapWidget(PhotoManagementViewModel viewModel, MainViewModel mainViewModel) {
    return ChangeNotifierProvider<PhotoManagementViewModel>.value(
      value: viewModel,
      child: ChangeNotifierProvider<MainViewModel>.value(
        value: mainViewModel,
        child: MaterialApp(
          localizationsDelegates: const [DefaultMaterialLocalizations.delegate],
          home: Scaffold(
            body: PhotoManagementPage(loginUser: _testLoginUser, child: mainViewModel.child),
          ),
        ),
      ),
    );
  }

  /// 搭设页面：可选预置照片与授权码，返回（页面 VM, 主 VM, 儿童 fake）。
  Future<(PhotoManagementViewModel, MainViewModel, _FakeChildService)> pumpPage(
    WidgetTester tester, {
    Set<String> operationCodes = const {},
    bool seedPhotos = false,
    bool selectChild = true,
  }) async {
    final childService = _FakeChildService(buildChildInfo());
    if (seedPhotos) {
      childService.saveDirect('child-1', avatar: base64Encode(_jpegBytes), thumb: base64Encode(_jpegBytes), createTime: '2026-11-10 10:00:00');
      childService.saveDirect('child-1', avatar: base64Encode(_jpegBytes), thumb: base64Encode(_jpegBytes), createTime: '2026-11-20 10:00:00');
    }
    final mainViewModel = MainViewModel(childService: childService);
    final viewModel = PhotoManagementViewModel(
      childService: childService,
      menuService: _FakeMenuService(operationCodes: operationCodes),
    );

    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    if (selectChild) {
      mainViewModel.setCurrentChild(buildChildInfo());
    }
    await tester.pumpWidget(wrapWidget(viewModel, mainViewModel));
    // 首帧回调（权限 + 列表装载）与侧边栏异步加载完成
    await tester.pumpAndSettle();
    return (viewModel, mainViewModel, childService);
  }

  testWidgets('未选定儿童：空态提示，拍照/上传/下载/删除全部灰化', (tester) async {
    await pumpPage(tester, selectChild: false);

    expect(find.text('未选定儿童——请先在主界面顶部搜索选定'), findsOneWidget);
    expect(find.text('请先在主界面顶部搜索选定儿童'), findsOneWidget);
    final captureButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '拍照'));
    expect(captureButton.onPressed, isNull);
    final uploadButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '上传'));
    expect(uploadButton.onPressed, isNull);
  });

  testWidgets('无操作权限：选定儿童后按钮仍全部灰化（tooltip 提示无权限）', (tester) async {
    await pumpPage(tester, selectChild: true);

    expect(find.text('暂无照片，可拍照或上传本地照片'), findsOneWidget);
    final captureButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '拍照'));
    expect(captureButton.onPressed, isNull);
    final deleteButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除'));
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('授权齐备 + 照片列表：卡片渲染、单击选中、下载/删除解锁', (tester) async {
    final (viewModel, _, _) = await pumpPage(
      tester,
      operationCodes: {
        PhotoManagementViewModel.opCapture,
        PhotoManagementViewModel.opUpload,
        PhotoManagementViewModel.opDownload,
        PhotoManagementViewModel.opDelete,
      },
      seedPhotos: true,
    );

    // 两条卡片（倒序最新在前）：拍摄年龄标签 + 创建人
    expect(find.text('张医生'), findsNWidgets(2));
    expect(find.textContaining('天'), findsNWidgets(2), reason: '拍摄年龄含「天」段（如「2天」/「12天」）');
    expect(find.byType(Image), findsNWidgets(2));

    // 按钮可用
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '拍照')).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '上传')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下载')).onPressed, isNull, reason: '未选中照片前下载灰化');
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除')).onPressed, isNull, reason: '未选中照片前删除灰化');

    // 单击首张卡片（最新一条）→ 选中高亮，下载/删除解锁。
    // 卡片同时注册 onTap/onDoubleTap，单击回调要等双击判定窗口
    // （kDoubleTapTimeout≈300ms）过后才触发，须显式推进时钟。
    await tester.tap(find.text('张医生').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(viewModel.selectedId, viewModel.photos.first.id);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下载')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除')).onPressed, isNotNull);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // 再次单击同一张 → 取消选中，下载/删除回到灰化
    await tester.tap(find.text('张医生').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(viewModel.selectedId, isNull);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下载')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除')).onPressed, isNull);
  });

  testWidgets('删除确认对话框：确认后按 ID 删除并刷新列表', (tester) async {
    final (viewModel, _, childService) = await pumpPage(
      tester,
      operationCodes: {PhotoManagementViewModel.opCapture, PhotoManagementViewModel.opUpload, PhotoManagementViewModel.opDownload, PhotoManagementViewModel.opDelete},
      seedPhotos: true,
    );

    // 选中首张（单击回调须越过双击判定窗口，见上）→ 删除 → 确认对话框
    await tester.tap(find.text('张医生').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final targetId = viewModel.selectedId;
    await tester.tap(find.widgetWithText(OutlinedButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除照片'), findsOneWidget);
    expect(find.textContaining('确定删除吗'), findsOneWidget);

    // 对话框内点【删除】（FilledButton，与工具栏描边按钮区分）→ 删除并刷新
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(childService.deleteCalls, 1);
    expect(viewModel.selectedId, isNull);
    expect(find.text('删除照片'), findsNothing, reason: '确认后对话框关闭');
    expect(find.text('张医生'), findsOneWidget, reason: '列表刷新后仅剩一条');
    expect(viewModel.photos.first.id, isNot(targetId));
  });
}
