// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../main.dart' as entrypoint;
import '../routes/index.dart' as index;
import '../routes/health.dart' as health;
import '../routes/api/index.dart' as api_index;
import '../routes/api/logs/index.dart' as api_logs_index;
import '../routes/api/hospital/update.dart' as api_hospital_update;
import '../routes/api/hospital/query.dart' as api_hospital_query;
import '../routes/api/hospital/delete.dart' as api_hospital_delete;
import '../routes/api/hospital/add.dart' as api_hospital_add;
import '../routes/api/auth/me.dart' as api_auth_me;
import '../routes/api/auth/login.dart' as api_auth_login;
import '../routes/api/adminDivision/update.dart' as api_admin_division_update;
import '../routes/api/adminDivision/query.dart' as api_admin_division_query;
import '../routes/api/adminDivision/delete.dart' as api_admin_division_delete;
import '../routes/api/adminDivision/add.dart' as api_admin_division_add;

import '../routes/_middleware.dart' as middleware;
import '../routes/api/logs/_middleware.dart' as api_logs_middleware;
import '../routes/api/hospital/_middleware.dart' as api_hospital_middleware;
import '../routes/api/auth/_middleware.dart' as api_auth_middleware;
import '../routes/api/adminDivision/_middleware.dart' as api_admin_division_middleware;

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
    ..mount('/api/hospital', (context) => buildApiHospitalHandler()(context))
    ..mount('/api/auth', (context) => buildApiAuthHandler()(context))
    ..mount('/api/adminDivision', (context) => buildApiAdminDivisionHandler()(context));
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

Handler buildApiHospitalHandler() {
  final pipeline = const Pipeline().addMiddleware(api_hospital_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_hospital_add.onRequest(context,))..all('/delete', (context) => api_hospital_delete.onRequest(context,))..all('/query', (context) => api_hospital_query.onRequest(context,))..all('/update', (context) => api_hospital_update.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAuthHandler() {
  final pipeline = const Pipeline().addMiddleware(api_auth_middleware.middleware);
  final router = Router()
    ..all('/login', (context) => api_auth_login.onRequest(context,))..all('/me', (context) => api_auth_me.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildApiAdminDivisionHandler() {
  final pipeline = const Pipeline().addMiddleware(api_admin_division_middleware.middleware);
  final router = Router()
    ..all('/add', (context) => api_admin_division_add.onRequest(context,))..all('/delete', (context) => api_admin_division_delete.onRequest(context,))..all('/query', (context) => api_admin_division_query.onRequest(context,))..all('/update', (context) => api_admin_division_update.onRequest(context,));
  return pipeline.addHandler(router);
}

