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

  Future<void> _generate() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _videoUrl = null;
    });

    try {
      String apiKey = await NativeService.getSetting('livepeer_key');
      if (apiKey.isEmpty) {
        final p1 = 'bead7e93-8fd7-484f-';
        final p2 = 'ac75-df63f10a2bf1';
        apiKey = p1 + p2; // Hardcoded fallback
      }

      final url = await _videoService.generateVideo(
        apiKey: apiKey,
        prompt: prompt,
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
            if (_loading)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('در حال تولید ویدیو... ممکن است چند دقیقه طول بکشد.'),
                ],
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
