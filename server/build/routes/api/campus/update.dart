import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/campus_service.dart';

/// POST /api/campus/update
/// 请求体：{id, ...要修改的字段}——可修改字段为 add 的业务字段
/// （hospId/code/name/address/tel），值 null 表示清空该列
/// （仅 address/tel 可空）；hospId 可改表示调整归属医院。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final id = body['id'];
  if (id is! String || id.trim().isEmpty) {
    return _error(400, 40001, '院区ID不能为空');
  }

  // 只把已知业务字段透传给服务层，其余键（含 id）一律拒绝
  const allowed = <String>{'hospId', 'code', 'name', 'address', 'tel'};
  final changes = <String, Object?>{
    for (final entry in body.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
  };
  if (changes.isEmpty) {
    return _error(400, 40001, '请至少修改一项院区信息');
  }
  for (final entry in changes.entries) {
    final v = entry.value;
    if (v != null && v is! String) {
      return _error(400, 40002, '字段 ${entry.key} 应为字符串');
    }
  }

  final service = context.read<CampusService>();
  try {
    final campus = await service.update(id.trim(), changes);
    return Response.json(
      body: {
        'code': 0,
        'message': '修改成功',
        'data': {'campus': campus.toJson()},
      },
    );
  } on CampusException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
