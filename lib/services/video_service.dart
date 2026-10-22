import 'dart:convert';
import 'package:http/http.dart' as http;

class VideoService {
  static const String _baseUrl = 'https://livepeer.studio/api/ai';

  /// Generates a video from a text prompt using Livepeer Studio AI.
  /// Returns the URL of the generated video.
  Future<String> generateVideo({
    required String apiKey,
    required String prompt,
    String modelId = 'stable-video-diffusion',
  }) async {
    final uri = Uri.parse('$_baseUrl/text-to-video');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prompt': prompt,
        'model_id': modelId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final dynamic body = jsonDecode(response.body);
      // Livepeer might return a task ID or a direct URL.
      // Based on 2026 docs, it returns a JSON with the asset URL or playback ID.
      final videoUrl = body['video_url'] as String?;
      if (videoUrl != null) return videoUrl;
      
      final assetId = body['asset_id'] as String?;
      if (assetId != null) {
         return 'https://lvpr.tv/?v=$assetId';
      }
      
      throw Exception('Video URL not found in response');
    } else {
      throw Exception('Livepeer Error: ${response.statusCode} - ${response.body}');
    }
  }
}
