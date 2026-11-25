import 'package:dart_frog/dart_frog.dart';
import 'package:server/models/api_body.dart';
import 'package:server/services/ai_guidance_service.dart';
import 'package:server/services/auth_service.dart';
import 'package:server/services/initial_screening_service.dart';

/// POST /api/initialScreening/aiGuidance
/// 请求体：{month, sex, warningSignResult, languageSocialCommunicationResult}。
/// 按年龄段与初筛发现调用 DeepSeek 生成健康宣教与干预指导（200 字内），
/// 返回 {guidance}。API Key 仅服务端持有（见 AiGuidanceService）。
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return _error(405, 40500, '该接口仅支持 POST 请求');
  }

  final body = context.read<ApiBody>().json;
  final month = (body['month'] as num?)?.toInt();
  if (month == null || month <= 0) {
    return _error(400, 40001, '月龄不能为空且应为正整数');
  }

  final authorization = context.request.headers['authorization'];
  final token = authorization?.startsWith('Bearer ') ?? false ? authorization!.substring('Bearer '.length).trim() : '';
  if (token.isEmpty) {
    return _error(401, 40101, '会话无效或已过期');
  }
  // 令牌无效时 verify 抛 AuthException（下方统一转换）
  await context.read<AuthService>().verify(token);

  final service = context.read<AiGuidanceService>();
  try {
    final guidance = await service.suggest(
      month: month,
      sex: (body['sex'] as String?) ?? '',
      warningSignResult: (body['warningSignResult'] as String?) ?? '',
      languageSocialResult: (body['languageSocialCommunicationResult'] as String?) ?? '',
    );
    return Response.json(
      body: {
        'code': 0,
        'message': 'ok',
        'data': {'guidance': guidance},
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
