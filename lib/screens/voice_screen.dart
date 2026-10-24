import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/native_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  bool _recording = false;
  bool _processing = false;
  String? _status;
  List<String> _separatedFiles = [];

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
      setState(() {
        _recording = false;
        _status = 'ضبط تمام شد. در حال آماده‌سازی برای پردازش...';
      });
      if (path != null) {
        _processAudio(path);
      }
    }
  }

  Future<void> _pickFile() async {
//     // file_picker 13.x: `FilePicker.platform` was removed in favour of static methods. // حذف موقت بخش پلتفرم برای بیلد موفق
    // pickFile() returns a single PlatformFile? (null when the user cancels).
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (path != null) {
      _processAudio(path);
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() {
      _processing = true;
      _status = 'در حال ارسال به سرور صوتی...';
    });

    try {
      final serverUrl = await NativeService.getSetting('voice_server_url', def: 'http://192.168.1.100:8000');
      
      var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/separate'));
      request.files.add(await http.MultipartFile.fromPath('file', path));

      var response = await request.send().timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        final jobId = data['job_id'];
        
        setState(() => _status = 'در حال پردازش در سرور (Demucs)...');
        
        // Poll for results
        while (true) {
          await Future.delayed(const Duration(seconds: 5));
          final statusRes = await http.get(Uri.parse('$serverUrl/status/$jobId'));
          if (statusRes.statusCode == 200) {
            final statusData = jsonDecode(statusRes.body);
            if (statusData['status'] == 'completed') {
              setState(() {
                _status = 'پردازش با موفقیت تمام شد!';
                _separatedFiles = List<String>.from(statusData['files']);
                _processing = false;
              });
              break;
            } else if (statusData['status'] == 'failed') {
              throw Exception('پردازش در سرور شکست خورد.');
            }
          }
        }
      } else {
        throw Exception('خطا در اتصال به سرور: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _status = 'خطا: ${e.toString()}';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('هوش مصنوعی صوتی (جداسازی)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_status != null)
                Text(_status!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 30),
              if (!_processing) ...[
                GestureDetector(
                  onLongPressStart: (_) => _toggleRecording(),
                  onLongPressEnd: (_) => _toggleRecording(),
                  child: FloatingActionButton.large(
                    onPressed: () {}, // Handled by LongPress
                    backgroundColor: _recording ? Colors.red : theme.colorScheme.primary,
                    child: Icon(_recording ? Icons.stop : Icons.mic, size: 40),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('برای ضبط نگه دارید'),
                const SizedBox(height: 30),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('انتخاب فایل صوتی از حافظه'),
                ),
              ] else
                const CircularProgressIndicator(),
              const SizedBox(height: 30),
              if (_separatedFiles.isNotEmpty) ...[
                const Text('فایل‌های جدا شده:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: _separatedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _separatedFiles[index];
                      return ListTile(
                        leading: const Icon(Icons.music_note),
                        title: Text(file),
                        trailing: IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            // TODO: Add audio player logic
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('در حال پخش: $file')),
                            );
                          },
                        ),
                      );
                    },
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
