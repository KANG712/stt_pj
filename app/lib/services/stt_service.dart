import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class SttService {
  static Future<Map<String, dynamic>> transcribe(String filePath) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/transcribe');

    final request = http.MultipartRequest('POST', uri)
      ..fields['language'] = 'ko'
      ..fields['beam_size'] = '5'
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: File(filePath).uri.pathSegments.last,
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      String message = 'STT 서버 오류: ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('서버 응답 형식이 올바르지 않습니다.');
    }

    return decoded;
  }
}