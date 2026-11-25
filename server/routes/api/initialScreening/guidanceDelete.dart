import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_guidance_service.dart';

/// POST /api/initialScreening/guidanceDelete
/// 请求体：{id}。删除指导建议模板（仅限创建人本人，他人模板统一 40001
/// 提示），返回删除行数。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能删除指导建议模板');
  }
  final id = (body['id'] as String?)?.trim() ?? '';
  if (id.isEmpty) {
    return _error(400, 40001, '模板ID不能为空');
  }

  final service = context.read<InitialScreeningGuidanceService>();
  try {
    final count = await service.delete(id, user!.id, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': '删除成功',
        'data': {'deleted': count},
      },
    );
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
