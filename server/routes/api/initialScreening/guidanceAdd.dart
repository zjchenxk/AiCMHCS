import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_guidance_service.dart';

/// POST /api/initialScreening/guidanceAdd
/// 请求体：{guidance, guidanceType, isPersonal}。新增本院指导建议模板
/// （创建人与医院/科室/院区归属从令牌会话推导，不信任客户端上报）。
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
    return _error(400, 40001, '当前登录用户未归属医院，不能新增指导建议模板');
  }

  final service = context.read<InitialScreeningGuidanceService>();
  try {
    final template = await service.create(
      guidance: (body['guidance'] as String?) ?? '',
      guidanceType: (body['guidanceType'] as String?) ?? '',
      isPersonal: (body['isPersonal'] as String?) ?? '1',
      operatorId: user!.id,
      operatorName: user.userName,
      hospId: hospId,
      hospName: user.hospName ?? '',
      deptId: user.deptId,
      deptName: user.deptName,
      campusId: user.campusId,
      campusName: user.campusName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': {'template': template.toJson()},
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
