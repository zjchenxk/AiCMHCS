import 'package:server/dm/dm_gateway.dart';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = context.read<DmGateway>();
  final stopwatch = Stopwatch()..start();
  try {
    await db.ping();
  } catch (e) {
    return Response.json(
      statusCode: 503,
      body: {
        'code': 50301,
        'message': '数据库不可用',
        'data': {'database': 'down', 'error': e.toString()},
      },
    );
  }
  stopwatch.stop();
  return Response.json(
    body: {
      'code': 0,
      'message': 'ok',
      'data': {
        'status': 'up',
        'database': 'DM8',
        'latencyMs': stopwatch.elapsedMilliseconds,
      },
    },
  );
}
