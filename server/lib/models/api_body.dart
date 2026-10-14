/// 已解密的 API 请求体明文（由 routes/api/_middleware.dart 解密信封后注入）。
///
/// dart_frog 的 RequestContext 不支持替换请求体，业务路由对非 GET 请求
/// 统一经 `context.read<ApiBody>().json` 取参，不要再直接 `request.json()`
/// （后者拿到的是密文信封）。非 GET 请求即使无请求体也会注入空对象。
final class ApiBody {
  /// 构造函数
  const ApiBody(this.json);

  /// 请求体明文 JSON 对象
  final Map<String, dynamic> json;
}
