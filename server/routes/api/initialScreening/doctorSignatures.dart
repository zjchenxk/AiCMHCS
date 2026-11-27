import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/doctorSignatures
/// 请求体：{doctorIds: [...]}。返回各检查医生的手写签名图（SYS_USER.
/// SIGNATURE_IMAGE base64，映射 {doctorId: base64}；无签名/不存在的
/// 医生不含在映射内），供初筛记录表/转诊单打印。医院从令牌会话推导，
/// 仅查本院 DOCTOR。
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
    return _error(400, 40001, '当前登录用户未归属医院，不能查询医生签名');
  }
  final idsRaw = body['doctorIds'];
  if (idsRaw is! List) {
    return _error(400, 40001, 'doctorIds 应为字符串数组');
  }
  final doctorIds = idsRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  if (doctorIds.isEmpty) {
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'signatures': const <String, String>{}},
      },
    );
  }

  final service = context.read<InitialScreeningService>();
  try {
    final signatures = await service.listDoctorSignatures(doctorIds, hospId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'signatures': signatures},
      },
    );
  } on AsdException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
