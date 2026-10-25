import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Livepeer Studio AI — text-to-video.
///
/// Real endpoints (verified: without a bearer header the route answers 404,
/// with one it answers 401 → the route exists):
///   POST https://livepeer.studio/api/ai/text-to-video      → {"task":{"id":"…"}}
///   GET  https://livepeer.studio/api/ai/text-to-video/{id} → {"status":"completed","output":{"url":"…"}}
///   GET  https://livepeer.studio/api/ai/models              → list of available models
///
/// The old implementation read `video_url` / `asset_id` from the create
/// response, which never exist — that is why the screen failed even with a
/// valid key.
class VideoService {
  static const String _baseUrl = 'https://livepeer.studio/api/ai';

  Map<String, String> _h(String key) => {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      };

  /// Checks that the key is accepted and the endpoint is reachable.
  /// Throws a readable Persian message otherwise.
  Future<List<String>> fetchModels(String apiKey) async {
    final res = await http
        .get(Uri.parse('$_baseUrl/models'), headers: _h(apiKey))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw VideoError(_explain(res.statusCode, res.body));
    }
    final body = jsonDecode(res.body);
    final list = body is List
        ? body
        : (body is Map && body['data'] is List)
            ? body['data'] as List
            : const [];
    final out = <String>[];
    for (final m in list) {
      if (m is String) {
        out.add(m);
      } else if (m is Map) {
        final id = m['id'] ?? m['model_id'] ?? m['name'];
        if (id != null) out.add(id.toString());
      }
    }
    return out;
  }

  /// Creates the task, then polls until the video is ready.
  Future<String> generateVideo({
    required String apiKey,
    required String prompt,
    String? modelId,
    int timeoutSeconds = 600,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw VideoError('کلید Livepeer وارد نشده — از تب تنظیمات وارد کن.');
    }

    final body = <String, dynamic>{'prompt': prompt};
    if (modelId != null && modelId.isNotEmpty) body['model_id'] = modelId;

    final create = await http
        .post(Uri.parse('$_baseUrl/text-to-video'),
            headers: _h(apiKey), body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));

    if (create.statusCode != 200 &&
        create.statusCode != 201 &&
        create.statusCode != 202) {
      throw VideoError(_explain(create.statusCode, create.body));
    }

    final json = jsonDecode(create.body);
    final taskId = _taskId(json);
    if (taskId == null) {
      throw VideoError(
          'پاسخ سرور قابل‌فهم نبود (task id پیدا نشد): ${create.body.toString().substring(0, _safe(create.body.toString().length, 200))}');
    }

    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      await Future.delayed(const Duration(seconds: 5));
      final res = await http
          .get(Uri.parse('$_baseUrl/text-to-video/$taskId'), headers: _h(apiKey))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        if (attempt > 3) {
          throw VideoError(_explain(res.statusCode, res.body));
        }
        continue;
      }
      final j = jsonDecode(res.body);
      final status = (j is Map ? j['status'] : null)?.toString().toLowerCase();
      if (status == 'failed' || status == 'error') {
        throw VideoError('ساخت ویدیو ناموفق بود: ${_brief(j)}');
      }
      final url = _outputUrl(j);
      if (url != null) return url;
      if (status == 'completed') {
        throw VideoError('ویدیو آماده شد ولی آدرس خروجی در پاسخ نبود: ${_brief(j)}');
      }
    }
    throw VideoError('مهلت تمام شد ($timeoutSeconds ثانیه) — کار هنوز در صف است.');
  }

  String? _taskId(dynamic j) {
    if (j is! Map) return null;
    final task = j['task'];
    if (task is Map && task['id'] != null) return task['id'].toString();
    if (task is String) return task;
    if (j['id'] != null) return j['id'].toString();
    return null;
  }

  String? _outputUrl(dynamic j) {
    if (j is! Map) return null;
    final output = j['output'];
    if (output is Map) {
      final u = output['url'] ?? output['video_url'] ?? output['hls_url'];
      if (u != null) return u.toString();
    }
    final direct = j['url'] ?? j['video_url'];
    if (direct != null) return direct.toString();
    final assets = j['assets'];
    if (assets is List && assets.isNotEmpty) {
      final a = assets.first;
      if (a is Map) {
        final u = a['playbackUrl'] ?? a['downloadUrl'] ?? a['url'];
        if (u != null) return u.toString();
      }
    }
    return null;
  }

  String _explain(int code, String body) {
    final b = _brief(body);
    if (code == 401 || code == 403) {
      return 'کلید Livepeer رد شد (HTTP $code): $b — کلید را از studio.livepeer.io بساز و دوباره وارد کن.';
    }
    if (code == 404) {
      return 'آدرس API پیدا نشد (HTTP 404): $b';
    }
    if (code == 402) {
      return 'اعتبار حساب کافی نیست (HTTP 402): $b';
    }
    if (code == 429) {
      return 'سقف درخواست (HTTP 429): $b — کمی بعد دوباره تلاش کن.';
    }
    return 'خطای Livepeer (HTTP $code): $b';
  }

  String _brief(dynamic v) {
    final s = v is String ? v : jsonEncode(v);
    final one = s.replaceAll(RegExp(r'\s+'), ' ');
    return one.substring(0, _safe(one.length, 220));
  }

  int _safe(int n, int max) => n > max ? max : n;
}

class VideoError implements Exception {
  final String message;
  VideoError(this.message);
  @override
  String toString() => message;
}
