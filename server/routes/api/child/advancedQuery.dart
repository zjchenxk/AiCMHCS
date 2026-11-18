import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/child_service.dart';

/// POST /api/child/advancedQuery
/// 高级组合查询本院儿童档案：{checkTimeFrom?, checkTimeTo?, birthDateFrom?,
/// birthDateTo?, name?, sex?, visitCardNo?, certificateNo?, phone?,
/// guardianName?, gestationalWeekFrom?, gestationalWeekTo?, birthWeightFrom?,
/// birthWeightTo?, page?, pageSize?}，条件之间为「与」关系（姓名/证件号码/
/// 电话号码/监护人姓名走盲索引精确匹配，不支持模糊），服务端分页返回
/// data: {children, total, page, pageSize}。医院从令牌会话推导（不信任
/// 客户端上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  // 请求体已被加密中间件解开为明文（勿直接 request.json()，那是密文）。
  final body = context.read<ApiBody>().json;

  // 登录用户从令牌会话推导（verify 失败由加密中间件的会话校验前置拦截）。
  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能查询儿童档案');
  }

  final service = context.read<ChildService>();
  try {
    final (children, total, page, pageSize) = await service.advancedQuery(
      hospId: hospId,
      checkTimeFrom: body['checkTimeFrom']?.toString(),
      checkTimeTo: body['checkTimeTo']?.toString(),
      birthDateFrom: body['birthDateFrom']?.toString(),
      birthDateTo: body['birthDateTo']?.toString(),
      name: body['name']?.toString(),
      sex: body['sex']?.toString(),
      visitCardNo: body['visitCardNo']?.toString(),
      certificateNo: body['certificateNo']?.toString(),
      phone: body['phone']?.toString(),
      guardianName: body['guardianName']?.toString(),
      gestationalWeekFrom: _intParam(body['gestationalWeekFrom']),
      gestationalWeekTo: _intParam(body['gestationalWeekTo']),
      birthWeightFrom: _intParam(body['birthWeightFrom']),
      birthWeightTo: _intParam(body['birthWeightTo']),
      page: _intParam(body['page']) ?? 1,
      pageSize: _intParam(body['pageSize']) ?? 20,
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'children': children.map((c) => c.toJson()).toList(),
          'total': total,
          'page': page,
          'pageSize': pageSize,
        },
      },
    );
  } on ChildException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  } on AuthException catch (e) {
    return _error(e.httpStatus, e.code, e.message);
  }
}

/// 数值入参解析：JSON 数字或数字字符串，空值/非法文本返回 null（交给
/// 服务层按可选项处理）。
int? _intParam(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  final v = value.toString().trim();
  if (v.isEmpty) return null;
  return int.tryParse(v);
}

Response _error(int status, int code, String message) => Response.json(
  statusCode: status,
  body: {'code': code, 'message': message, 'data': null},
);
