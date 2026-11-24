import 'package:common/model.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/save
/// 请求体：{record: {...}}。新增或修改当前儿童的某一时段初筛记录
/// （同一儿童同一检查时段至多一条，服务层查重后走 UPDATE 或 INSERT）；
/// 归属医院/创建人与科室/院区上下文从令牌会话推导，不信任客户端上报。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final recordJson = body['record'];
  if (recordJson is! Map<String, dynamic>) {
    return _error(400, 40001, '初筛记录不能为空');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能保存初筛记录');
  }

  final service = context.read<InitialScreeningService>();
  try {
    final record = await service.save(
      record: InitialScreening.fromJson(recordJson),
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
        'message': '保存成功',
        'data': {'record': record.toJson()},
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
