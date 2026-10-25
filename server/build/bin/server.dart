// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../main.dart' as entrypoint;
import '../routes/index.dart' as index;
import '../routes/health.dart' as health;
import '../routes/api/index.dart' as api_index;
import '../routes/api/logs/index.dart' as api_logs_index;
import '../routes/api/auth/me.dart' as api_auth_me;
import '../routes/api/auth/login.dart' as api_auth_login;
import '../routes/api/admin-divisions/index.dart' as api_admin_divisions_index;
import '../routes/api/admin-divisions/[code].dart' as api_admin_divisions_$code;

import '../routes/_middleware.dart' as middleware;
import '../routes/api/logs/_middleware.dart' as api_logs_middleware;
import '../routes/api/auth/_middleware.dart' as api_auth_middleware;
import '../routes/api/admin-divisions/_middleware.dart' as api_admin_divisions_middleware;

void main() async {
  final address = InternetAddress.anyIPv6;
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  createServer(address, port);
}

Future<HttpServer> createServer(InternetAddress address, int port) async {
  final handler = Cascade().add(buildRootHandler()).handler;
  final server = await entrypoint.run(handler, address, port);
  print('\x1B[92m✓\x1B[0m Running on http://${server.address.host}:${server.port}');
  return server;
}

Handler buildRootHandler() {
  final pipeline = const Pipeline().addMiddleware(middleware.middleware);
  final router = Router()
    ..mount('/', (context) => buildHandler()(context))
    ..mount('/api', (context) => buildApiHandler()(context))
    ..mount('/api/logs', (context) => buildApiLogsHandler()(context))
    ..mount('/api/auth', (context) => buildApiAuthHandler()(context))
    ..mount('/api/admin-divisions', (context) => buildApiAdminDivisionsHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/health', (context) => health.onRequest(context,))..all('/', (context) => index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => api_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiLogsHandler() {
  final pipeline = const Pipeline().addMiddleware(api_logs_middleware.middleware);
  final router = Router()
    ..all('/', (context) => api_logs_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAuthHandler() {
  final pipeline = const Pipeline().addMiddleware(api_auth_middleware.middleware);
  final router = Router()
    ..all('/login', (context) => api_auth_login.onRequest(context,))..all('/me', (context) => api_auth_me.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAdminDivisionsHandler() {
  final pipeline = const Pipeline().addMiddleware(api_admin_divisions_middleware.middleware);
  final router = Router()
    ..all('/<code>', (context,code,) => api_admin_divisions_$code.onRequest(context,code,))..all('/', (context) => api_admin_divisions_index.onRequest(context,));
  return pipeline.addHandler(router);
}

