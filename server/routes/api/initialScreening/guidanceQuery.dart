import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_guidance_service.dart';

/// POST /api/initialScreening/guidanceQuery
/// 请求体：空对象。返回本院可见的孤独症初筛指导建议模板（公共模板 +
/// 本人个人模板，按创建时间倒序），供指导建议【选择模板】对话框。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能查询指导建议模板');
  }

  final service = context.read<InitialScreeningGuidanceService>();
  try {
    final templates = await service.listByHospital(hospId, user!.id);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'templates': templates.map((t) => t.toJson()).toList()},
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
