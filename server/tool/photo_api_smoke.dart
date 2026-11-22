// 儿童照片管理 API 链路冒烟脚本：走真实 HTTP + 信封加密，覆盖照片管理
// 四个动作式路由的完整链路（建档带首拍 → photoSave 独立保存 → photoList
// 列表（缩略图/无大图/倒序）→ photoDetail 详情（大图+缩略图）→
// photoDelete 按 ID 删除，最后清理冒烟档案）。
// 用法：后端启动后 cd server && dart run tool/photo_api_smoke.dart
import 'dart:convert';

import 'package:common/utils/security_helper.dart';
import 'package:http/http.dart' as http;

const baseUrl = 'http://localhost:8080';

Future<void> main() async {
  final client = http.Client();

  // 1. 明文登录拿 token + sessionKey（登录须携带所选角色 ID——主键为
  // UUID v7，先经白名单明文接口 /api/auth/roles 拉取该用户角色列表）
  final rolesResp = await client.get(
    Uri.parse('$baseUrl/api/auth/roles?usercode=admin'),
  );
  final roles = ((jsonDecode(rolesResp.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>)['roles'] as List<dynamic>;
  if (roles.isEmpty) {
    throw StateError('admin 无可选角色，请先执行 seed_demo_data');
  }
  final roleId = (roles.first as Map<String, dynamic>)['id'] as String;
  final loginResp = await client.post(
    Uri.parse('$baseUrl/api/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'usercode': 'admin', 'password': 'Admin@123', 'role': roleId}),
  );
  final loginData = _unwrapPlain(loginResp);
  final token = loginData['token'] as String;
  final sessionKey = loginData['sessionKey'] as String;
  print('1. 登录成功 token=${token.substring(0, 8)}...');

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool allowFailure = false}) async {
    final sealedBody = await SecurePayload.seal(sessionKey, body);
    final resp = await client.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(sealedBody),
    );
    var json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json.containsKey('payload')) {
      json = await SecurePayload.open(sessionKey, json);
    }
    print('   POST $path -> HTTP ${resp.statusCode} code=${json['code']} message=${json['message']}');
    if (json['code'] != 0) {
      if (allowFailure) return json;
      throw StateError('接口失败: ${json['message']}');
    }
    return (json['data'] as Map<String, dynamic>?) ?? const {};
  }

  final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
  String? childId;
  try {
    // 2. 建档并携带首拍记录（照片/头像/缩略图三件套）
    final created = await post('/api/child/add', {
      'child': {
        'checkTime': '2026-11-21',
        'visitCardNo': 'SMK$suffix',
        'name': '冒烟儿童$suffix',
        'sex': '1',
        'birthDate': '2026-01-01',
        'addressProvince': '110000',
        'addressCity': '110100',
        'addressCounty': '110101',
        'addressDetails': '冒烟测试路 1 号',
      },
      'photo': {'photoBase64': 'SMOKE-PHOTO-1', 'avatarBase64': 'SMOKE-AVATAR-1', 'thumbBase64': 'SMOKE-THUMB-1'},
    });
    childId = (created['child'] as Map<String, dynamic>)['id'] as String;
    print('2. 已建档 $childId（携带首拍）');

    // 3. photoSave 独立保存一条（照片管理页拍照/上传链路）
    final saved =
        (await post('/api/child/photoSave', {
              'childId': childId,
              'photoBase64': 'SMOKE-PHOTO-2',
              'avatarBase64': 'SMOKE-AVATAR-2',
              'thumbBase64': 'SMOKE-THUMB-2',
            }))['photo']
            as Map<String, dynamic>;
    print('3. photoSave 成功 id=${saved['id']} thumb=${saved['thumbBase64']}');

    // 4. photoList 列表：两条、倒序最新在前、带头像与缩略图、不含大图
    final photos = (await post('/api/child/photoList', {'childId': childId}))['photos'] as List<dynamic>;
    final avatars = photos.map((p) => (p as Map<String, dynamic>)['avatarBase64']).toList();
    final thumbs = photos.map((p) => (p as Map<String, dynamic>)['thumbBase64']).toList();
    final hasBigPhoto = photos.any((p) => (p as Map<String, dynamic>)['photoBase64'] != null);
    print('4. photoList ${photos.length} 条 avatars=$avatars thumbs=$thumbs 含大图: $hasBigPhoto');

    // 5. photoDetail 详情：回大图与缩略图
    final newestId = (photos.first as Map<String, dynamic>)['id'] as String;
    final detail = (await post('/api/child/photoDetail', {'photoId': newestId}))['photo'] as Map<String, dynamic>;
    print('5. photoDetail photo=${detail['photoBase64']} thumb=${detail['thumbBase64']}');

    // 6. photoDelete 按 ID 删除（删最新一条）
    final deleted = (await post('/api/child/photoDelete', {'photoId': newestId}))['deleted'] as int;
    final afterDelete = (await post('/api/child/photoList', {'childId': childId}))['photos'] as List<dynamic>;
    print('6. photoDelete deleted=$deleted，剩余 ${afterDelete.length} 条');

    if (photos.length != 2 || avatars.first != 'SMOKE-AVATAR-2' || hasBigPhoto) {
      throw StateError('链路断言失败：列表口径不符');
    }
    if (thumbs.contains(null) || detail['photoBase64'] != 'SMOKE-PHOTO-2' || detail['thumbBase64'] != 'SMOKE-THUMB-2') {
      throw StateError('链路断言失败：详情/缩略图不符');
    }
    if (deleted != 1 || afterDelete.length != 1) {
      throw StateError('链路断言失败：删除不符');
    }
  } finally {
    // 7. 清理：删冒烟档案（连带删除全部拍照记录）
    if (childId != null) {
      await post('/api/child/delete', {'id': childId}, allowFailure: true);
    }
    print('7. 清理完成');
    client.close();
  }

  print('全部链路正常');
}

Map<String, dynamic> _unwrapPlain(http.Response resp) {
  final json = jsonDecode(resp.body) as Map<String, dynamic>;
  if (json['code'] != 0) {
    throw StateError('登录失败: ${json['message']}');
  }
  return json['data'] as Map<String, dynamic>;
}
