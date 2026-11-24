import 'package:dart_frog/dart_frog.dart';
import 'package:server/middlewares/api_secure_middleware.dart';

Handler middleware(Handler next) => apiSecureMiddleware(next);
