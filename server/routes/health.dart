import 'package:dart_frog/dart_frog.dart';
import 'package:server/db/database_gateway.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = context.read<DatabaseGateway>();
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
        'database': switch (db.dialect) {
          DbDialect.dm => 'DM8',
          DbDialect.sqlite => 'SQLite',
        },
        'latencyMs': stopwatch.elapsedMilliseconds,
      },
    },
  );
}
