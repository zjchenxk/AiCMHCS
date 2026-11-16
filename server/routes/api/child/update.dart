import 'package:common/model.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/update
/// 请求体：{id, child: {...}, ext?: {...}, guardians?: [...]}
/// （整档保存：基本信息按入参全量更新，PATIENT_ID/归属/创建人不可改；
/// ext 缺省表示清空扩展信息；扩展信息与监护人先删后插全量覆盖）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = (body['id'] as String?)?.trim() ?? '';
  if (id.isEmpty) {
    return _error(400, 40001, '儿童ID不能为空');
  }
  final childJson = body['child'];
  if (childJson is! Map<String, dynamic>) {
    return _error(400, 40001, '儿童基本信息不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能修改儿童档案');
  }

  final service = context.read<ChildService>();
  try {
    final (child, ext, guardians) = await service.update(
      id: id,
      child: ChildInfo.fromJson(childJson),
      ext: parseExt(body['ext']),
      guardians: parseGuardians(body['guardians']),
      photoBase64: parsePhotoField(body['photo'], 'photoBase64'),
      avatarBase64: parsePhotoField(body['photo'], 'avatarBase64'),
      hospId: hospId,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '修改成功',
        'data': {
          'child': child.toJson(),
          'ext': ext?.toJson(),
          'guardians': guardians.map((g) => g.toJson()).toList(),
        },
      },
    );
  } on ChildException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

/// 解析请求体中的扩展信息（缺失或非对象时为 null，表示清空扩展信息）。
ChildExtInfo? parseExt(Object? value) {
  if (value is Map<String, dynamic>) {
    return ChildExtInfo.fromJson(value);
  }
  return null;
}

/// 解析请求体中的监护人列表（缺失或元素非对象时忽略）。
List<ChildGuardianInfo> parseGuardians(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<Map<String, dynamic>>().map(ChildGuardianInfo.fromJson).toList();
}

/// 解析拍照对象中的 base64 字段（photo 缺失或字段缺失时为 null，表示
/// 本次保存不带照片）。
String? parsePhotoField(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    final v = value[field];
    if (v is String && v.trim().isNotEmpty) {
      return v.trim();
    }
  }
  return null;
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
