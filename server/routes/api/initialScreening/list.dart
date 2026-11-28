import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';
import 'package:server/utils/field_cipher.dart';

/// POST /api/initialScreening/list
/// 请求体：{startDate?, endDate?, page?, pageSize?}。侧边栏「初筛儿童」
/// 分页列表：本院全部初筛记录按检查日期倒序返回（含解密后的儿童姓名），
/// 日期区间均不传时查询全部记录。医院从令牌会话推导（不信任客户端
/// 上报）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;

  // 日期区间：格式校验（yyyy-MM-dd），非法一律 40001
  final startDate = (body['startDate'] as String?)?.trim() ?? '';
  final endDate = (body['endDate'] as String?)?.trim() ?? '';
  final datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (startDate.isNotEmpty && !datePattern.hasMatch(startDate)) {
    return _error(400, 40001, '起始日期格式应为 yyyy-MM-dd');
  }
  if (endDate.isNotEmpty && !datePattern.hasMatch(endDate)) {
    return _error(400, 40001, '截止日期格式应为 yyyy-MM-dd');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : null;
  final user = token == null ? null : await context.read<AuthService>().verify(token);
  final hospId = user?.hospId?.trim() ?? '';
  if (hospId.isEmpty) {
    return _error(400, 40001, '当前登录用户未归属医院，不能查询初筛记录列表');
  }

  final page = (body['page'] as num?)?.toInt() ?? 1;
  final pageSize = (body['pageSize'] as num?)?.toInt() ?? 10;

  final service = context.read<InitialScreeningService>();
  try {
    final (records, total, safePage, safePageSize) = await service.listForSidebar(
      hospId: hospId,
      startDate: startDate.isEmpty ? null : startDate,
      endDate: endDate.isEmpty ? null : endDate,
      page: page,
      pageSize: pageSize,
      cipher: context.read<FieldCipher>(),
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {
          'records': records.map((r) => r.toJson()).toList(),
          'total': total,
          'page': safePage,
          'pageSize': safePageSize,
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
