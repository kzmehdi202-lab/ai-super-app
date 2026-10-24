import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../services/native_service.dart';

/// هوش مصنوعی صوتی — جداسازی وکال (Demucs) و کلون صدا (OpenVoice v2)
/// پردازش روی GitHub Actions انجام می‌شود؛ اپ فقط آپلود و دریافت نتیجه می‌کند.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  static const String ghRepo = 'liberto';

  bool _recording = false;
  bool _busy = false;
  String? _status;
  String? _sourcePath;
  final List<_ResultItem> _results = [];
  final AudioPlayer _player = AudioPlayer();

  Future<_GhConfig?> _gh() async {
    final token = await NativeService.getSetting('github_token');
    if (token.isEmpty) return null;
    String owner = await NativeService.getSetting('github_user');
    if (owner.isEmpty) owner = 'kzmehdi202-lab';
    return _GhConfig(owner: owner, token: token);
  }

  Future<void> _toggleRecording() async {
    if (!_recording) {
      if (!await NativeService.hasAudioPermission()) {
        await NativeService.requestAudioPermission();
        return;
      }
      final path = await NativeService.startRecording();
      if (path != null) {
        setState(() {
          _recording = true;
          _status = 'در حال ضبط...';
        });
      }
    } else {
      final path = await NativeService.stopRecording();
      setState(() => _recording = false);
      if (path != null) {
        setState(() {
          _sourcePath = path;
          _status = 'صدا ضبط شد. حالا «جداسازی» یا «کلون» را انتخاب کنید.';
        });
      }
    }
  }

  Future<void> _pickFile() async {
    // file_picker 13.x: متد استاتیک pickFile
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (path != null && mounted) {
      setState(() {
        _sourcePath = path;
        _status = 'فایل انتخاب شد. «جداسازی» یا «کلون» را بزنید.';
      });
    }
  }

  Future<void> _pickRef() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file?.path != null) _refPath = file!.path;
    if (mounted) {
      setState(() => _status = _refPath == null
          ? 'رفرنس انتخاب نشد'
          : 'فایل رفرنس (صدای مقصد) انتخاب شد ✓');
    }
  }

  String? _refPath;

  Future<void> _separate() async {
    final src = _sourcePath;
    final cfg = await _gh();
    if (src == null || !mounted) return;
    if (cfg == null) {
      setState(() => _status = 'توکن GitHub تنظیم نشده — اول از تب تنظیمات توکن را وارد کنید');
      return;
    }
    setState(() { _busy = true; _results.clear(); _status = 'در حال آپلود روی گیت‌هاب...'; });
    try {
      final id = 'v${DateTime.now().millisecondsSinceEpoch}';
      final ext = _extOf(src);
      await _ghUpload(cfg, 'audio_jobs/$id.$ext', src, 'audio job: $id');
      if (!mounted) return;
      setState(() => _status =
          'روی سرور ابری در حال جداسازی است (Demucs) — حدود ۸ تا ۱۵ دقیقه. می‌توانید صفحه را ببندید؛ نتیجه همان لحظه ذخیره می‌شود.');

      final found = await _pollRaw(cfg, [
        'results/${id}_vocals.m4a',
        'results/${id}_accompaniment.m4a',
      ], attempts: 60, delaySec: 20);
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() { _status = 'نتیجه در زمان مقرر نیامد. بعداً دوباره امتحان کنید.'; _busy = false; });
        return;
      }
      await _saveAndList(cfg, found, {'_vocals': 'وکال (صدای خواننده)', '_accompaniment': 'بی‌کلام (آهنگ)'});
      if (!mounted) return;
      setState(() { _busy = false; _status = 'جداسازی تمام شد ✓'; });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _clone() async {
    final src = _sourcePath;
    final ref = _refPath;
    final cfg = await _gh();
    if (!mounted) return;
    if (src == null || ref == null) {
      setState(() => _status = 'اول «صدای منبع» بعد «فایل رفرنس مقصد» را انتخاب کنید');
      return;
    }
    if (cfg == null) {
      setState(() => _status = 'توکن GitHub تنظیم نشده — اول از تب تنظیمات توکن را وارد کنید');
      return;
    }
    setState(() { _busy = true; _results.clear(); _status = 'در حال آپلود جفت فایل روی گیت‌هاب...'; });
    try {
      final id = 'c${DateTime.now().millisecondsSinceEpoch}';
      await _ghUpload(cfg, 'clone_jobs/$id/source.${_extOf(src)}', src, 'clone src: $id');
      await _ghUpload(cfg, 'clone_jobs/$id/ref.${_extOf(ref)}', ref, 'clone ref: $id');
      if (!mounted) return;
      setState(() => _status =
          'روی سرور ابری در حال کلون صدا است (OpenVoice v2) — حدود ۲۰ تا ۴۰ دقیقه.');
      final found = await _pollRaw(cfg, ['results/${id}_clone.m4a'],
          attempts: 100, delaySec: 30);
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() { _status = 'نتیجه کلون در زمان مقرر نیامد.'; _busy = false; });
        return;
      }
      await _saveAndList(cfg, found, {'_clone': 'صدای کلون‌شده'});
      if (!mounted) return;
      setState(() { _busy = false; _status = 'کلون صدا تمام شد ✓'; });
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    final s = e.toString();
    setState(() {
      _busy = false;
      _status = s.contains('401') || s.contains('403')
          ? 'توکن GitHub نامعتبر یا منقضی است — از تنظیمات توکن تازه بگذارید'
          : 'خطا: $s';
    });
  }

  String _extOf(String p) {
    final e = p.split('.').last.toLowerCase();
    const ok = {'m4a', 'mp3', 'wav', 'aac', 'ogg', '3gp'};
    return ok.contains(e) ? e : 'm4a';
  }

  Future<void> _ghUpload(_GhConfig cfg, String path, String localFile, String msg) async {
    final bytes = await File(localFile).readAsBytes();
    final body = jsonEncode({'message': msg, 'content': base64Encode(bytes)});
    final res = await http.put(
      Uri.parse('https://api.github.com/repos/${cfg.owner}/$ghRepo/contents/$path'),
      headers: {
        'Authorization': 'token ${cfg.token}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: body,
    ).timeout(const Duration(minutes: 5));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('آپلود شکست خورد (${res.statusCode})');
    }
  }

  Future<List<String>> _pollRaw(_GhConfig cfg, List<String> paths,
      {required int attempts, required int delaySec}) async {
    final pending = paths.toList();
    final done = <String>[];
    for (var i = 0; i < attempts && pending.isNotEmpty; i++) {
      await Future.delayed(Duration(seconds: i == 0 ? 15 : delaySec));
      for (final p in pending.toList()) {
        final url =
            'https://raw.githubusercontent.com/${cfg.owner}/$ghRepo/main/$p';
        try {
          final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
          if (r.statusCode == 200) {
            done.add(p);
            pending.remove(p);
          }
        } catch (_) {}
      }
      if (!mounted) return done;
    }
    return done;
  }

  Future<void> _saveAndList(_GhConfig cfg, List<String> paths, Map<String, String> labels) async {
    final dir = await getApplicationDocumentsDirectory();
    for (final p in paths) {
      final r = await http.get(Uri.parse(
          'https://raw.githubusercontent.com/${cfg.owner}/$ghRepo/main/$p'));
      if (r.statusCode == 200) {
        final name = p.split('/').last;
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(r.bodyBytes);
        String label = name;
        for (final e in labels.entries) {
          if (name.contains(e.key)) { label = e.value; break; }
        }
        _results.add(_ResultItem(label: label, path: f.path));
      }
    }
  }

  Future<void> _play(_ResultItem item) async {
    try {
      await _player.stop();
      await _player.setFilePath(item.path);
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'پخش ناموفق: $e');
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('هوش مصنوعی صوتی')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_status != null)
                Text(_status!, textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              if (!_busy) ...[
                GestureDetector(
                  onLongPressStart: (_) => _toggleRecording(),
                  onLongPressEnd: (_) => _toggleRecording(),
                  child: FloatingActionButton.large(
                    onPressed: () {},
                    backgroundColor: _recording ? Colors.red : theme.colorScheme.primary,
                    child: Icon(_recording ? Icons.stop : Icons.mic, size: 40),
                  ),
                ),
                const SizedBox(height: 8),
                Text(_recording ? 'برای توقف، انگشت را بردارید' : 'برای ضبط صدای خود نگه دارید'),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.music_note),
                  label: Text(_sourcePath == null
                      ? 'انتخاب آهنگ/صدا از حافظه (منبع)'
                      : 'منبع انتخاب شده ✓ — عوض کردن'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickRef,
                  icon: const Icon(Icons.record_voice_over),
                  label: Text(_refPath == null
                      ? 'انتخاب صدای مقصد برای کلون (اختیاری)'
                      : 'رفرنس مقصد انتخاب شد ✓'),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.icon(
                      onPressed: _sourcePath == null ? null : _separate,
                      icon: const Icon(Icons.call_split),
                      label: const Text('جداسازی وکال'),
                    ),
                    FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('کلون صدا (به‌زودی)'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'پردازش روی سرور ابری رایگان گیت‌هاب انجام می‌شود — در اینترنت وای‌فای انجام دهید.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('در حال پردازش — صفحه را نبندید یا اگر بستید، نتیجه خودکار ذخیره می‌شود.',
                    textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: const Icon(Icons.audiotrack),
                      title: Text(_results[i].label),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _play(_results[i]),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GhConfig {
  final String owner;
  final String token;
  const _GhConfig({required this.owner, required this.token});
}

class _ResultItem {
  final String label;
  final String path;
  const _ResultItem({required this.label, required this.path});
}
