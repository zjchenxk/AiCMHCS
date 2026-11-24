import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/holiday_service.dart';

/// POST /api/holiday/add
/// 请求体：{startDate, endDate, holidayType}（起止日期必填且为
/// yyyy-MM-dd、起始不得晚于截止；类型 1-8）。医院与创建人从令牌会话
/// 推导，不信任客户端上报。主键为数据库自增，新增后不回读，客户端
/// 整表重拉。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;
  final startDate = body['startDate'];
  final endDate = body['endDate'];
  final holidayType = body['holidayType'];
  if (startDate is! String || startDate.trim().isEmpty) {
    return _error(400, 40001, '起始日期不能为空');
  }
  if (endDate is! String || endDate.trim().isEmpty) {
    return _error(400, 40001, '截止日期不能为空');
  }
  final type = holidayType is int ? holidayType : int.tryParse(holidayType?.toString() ?? '');
  if (type == null) {
    return _error(400, 40001, '节假日类型不能为空');
  }

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能维护法定节假日');
  }

  final service = context.read<HolidayService>();
  try {
    await service.create(
      startDate: startDate,
      endDate: endDate,
      holidayType: type,
      hospId: hospId,
      hospName: user!.hospName ?? '',
      creatorId: user.id,
      creatorName: user.userName,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': '新增成功',
        'data': <String, Object?>{},
      },
    );
  } on HolidayException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
