import 'package:dart_frog/dart_frog.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/doctors
/// 请求体：空对象。返回当前登录用户所属科室的检查医生候选（同科室、
/// USER_TYPE=DOCTOR、未停用；科室从令牌会话推导，不信任客户端上报），
/// 供【检查医生】下拉选择。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final deptId = user?.deptId?.trim() ?? '';

  final service = context.read<InitialScreeningService>();
  try {
    final doctors = await service.listDoctors(deptId);
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'doctors': [
            for (final d in doctors) {'id': d.id, 'userCode': d.userCode, 'userName': d.userName},
          ],
        },
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
