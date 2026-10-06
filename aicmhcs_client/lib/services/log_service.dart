import 'dart:convert';
import 'package:aicmhcs_client/utils/security_util.dart';

class LogService {
  ///新增日志
  ///param type 日志类型
  ///param msg 日志内容
  ///returns
  Future<void> addLog(String type, String msg) async {
    var encryptedRequest = await SecurityUtil.encryptAES(jsonEncode({'level': type, 'message': msg}));
    var sign = SecurityUtil.generateMD5(encryptedRequest + SecurityUtil.secretKey + SecurityUtil.secretIV);

    //client.log.addLog(encryptedRequest, sign);
  }
}
