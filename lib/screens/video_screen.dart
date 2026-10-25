import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/native_service.dart';
import '../services/video_service.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final TextEditingController _promptCtrl = TextEditingController();
  final VideoService _videoService = VideoService();
  
  String? _videoUrl;
  bool _loading = false;
  String? _error;

  VideoPlayerController? _controller;

  List<String> _models = [];
  String? _model;
  bool _checking = false;
  String? _info;

  /// Preflight: proves the key is accepted and the API address is reachable,
  /// so "my token is wrong" can never be the answer again.
  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _error = null;
      _info = null;
    });
    try {
      final apiKey = await NativeService.getSetting('livepeer_key');
      if (apiKey.trim().isEmpty) {
        throw VideoError('کلید Livepeer ذخیره نشده — از تب «تنظیمات» وارد کن.');
      }
      final models = await _videoService.fetchModels(apiKey);
      setState(() {
        _models = models;
        if (_model == null && models.isNotEmpty) _model = models.first;
        _checking = false;
        _info = models.isEmpty
            ? 'کلید معتبر است، ولی فهرست مدل‌ها خالی برگشت.'
            : 'کلید معتبر و آدرس درست است — ${models.length} مدل در دسترس.';
      });
    } catch (e) {
      setState(() {
        _checking = false;
        _info = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _videoUrl = null;
    });

    try {
      final apiKey = await NativeService.getSetting('livepeer_key');
      if (apiKey.trim().isEmpty) {
        throw VideoError(
            'کلید Livepeer وارد نشده — از تب «تنظیمات» کلید studio.livepeer.io را وارد و ذخیره کن.');
      }

      final url = await _videoService.generateVideo(
        apiKey: apiKey,
        prompt: prompt,
        modelId: _model,
      );

      setState(() {
        _videoUrl = url;
        _loading = false;
      });

      _initPlayer(url);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _initPlayer(String url) {
    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        setState(() {});
        _controller?.play();
        _controller?.setLooping(true);
      });
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('تولید ویدیو AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _promptCtrl,
              decoration: InputDecoration(
                hintText: 'مثلاً: یک فضانورد در حال قدم زدن روی مریخ...',
                labelText: 'توضیح ویدیو (Prompt)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _loading ? null : _generate,
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkConnection,
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(_checking ? 'در حال بررسی…' : 'بررسی کلید و آدرس'),
                ),
                const SizedBox(width: 12),
                if (_models.isNotEmpty)
                  Expanded(
                    child: DropdownButton<String>(
                      value: _models.contains(_model) ? _model : _models.first,
                      isExpanded: true,
                      items: _models
                          .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _model = v),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('در حال تولید ویدیو... ممکن است چند دقیقه طول بکشد.'),
                ],
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_info!, style: const TextStyle(fontSize: 13)),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (_videoUrl != null) ...[
              const Text('ویدیو تولید شد!'),
              const SizedBox(height: 10),
              if (_controller != null && _controller!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(_controller!),
                      VideoProgressIndicator(_controller!, allowScrubbing: true),
                    ],
                  ),
                )
              else
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 10),
              SelectableText(_videoUrl!, style: const TextStyle(fontSize: 12, color: Colors.blue)),
            ],
          ],
        ),
      ),
    );
  }
}
