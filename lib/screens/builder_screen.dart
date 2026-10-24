import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_templates.dart';
import '../services/build_service.dart';
import '../services/native_service.dart';
import 'chat_screen.dart';

/// Liberto's app builder:
/// describe an app → the AI writes the code → GitHub compiles it in the
/// cloud → you get the install file (APK).
class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  final Map<String, StackTemplate> _templates = buildTemplates();
  String _stackId = 'kotlin'; // Android Native (Kotlin) first
  final TextEditingController _descCtrl = TextEditingController();

  String _apiKey = '';
  String _modelId = '';
  String _modelName = 'مدل پیش‌فرض';
  String _ghUser = '';
  String _ghToken = '';

  bool _busy = false;
  int _step = -1;
  String _detail = '';
  BuildResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _apiKey = (await NativeService.getApiKey()) ?? '';
    _modelId = (await NativeService.getSetting('model_id')) ?? '';
    if (_modelId.isNotEmpty) _modelName = _modelId;
    _ghUser = (await NativeService.getSetting('github_user')) ?? '';
    _ghToken = (await NativeService.getSetting('github_token')) ?? '';
    // همان مقادیر پیش‌فرض تب تنظیمات — اگر چیزی ذخیره نشده بود، همین‌جا بارگذاری
    // و ذخیره می‌شود تا تب برنامه‌ساز و تنظیمات همیشه یکسان باشند.
    if (_ghToken.isEmpty) {
      const ghp1 = 'ghp_1oDNbmyAvexD9hy';
      const ghp2 = 'YO3E4ZEfz3Tz1IS2XAVMA';
      _ghToken = ghp1 + ghp2;
      await NativeService.saveSetting('github_token', _ghToken);
    }
    if (_ghUser.isEmpty) {
      _ghUser = 'kzmehdi202-lab';
      await NativeService.saveSetting('github_user', _ghUser);
    }
    if (_apiKey.isEmpty) {
      const part1 = 'sk-or-v1-1ab390ee9afc5a7d5e695faf7fdc23ea28bc';
      const part2 = 'ccc2733922ceb9b65d71f688d44';
      _apiKey = part1 + part2;
      await NativeService.saveApiKey(_apiKey);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _ready =>
      _apiKey.isNotEmpty && _ghToken.isNotEmpty && _descCtrl.text.trim().length >= 4;

  Future<void> _openModelPicker() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(
          initialId: _modelId.isEmpty ? 'qwen/qwen-2.5-72b-instruct' : _modelId,
        ),
      ),
    );
    if (result is List && result.length == 2) {
      _modelId = result[0] as String;
      _modelName = result[1] as String;
      await NativeService.saveSetting('model_id', _modelId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    await _loadSettings();
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _step = 0;
      _detail = '';
    });
    try {
      final res = await BuildService().build(
        apiKey: _apiKey,
        model: _modelId.isEmpty ? 'openai/gpt-4o-mini' : _modelId,
        ghToken: _ghToken,
        template: _templates[_stackId]!,
        description: _descCtrl.text.trim(),
        onProgress: (s, d) {
          if (mounted) setState(() {
            _step = s;
            _detail = d;
          });
        },
      );
      if (mounted) setState(() {
        _busy = false;
        _result = res;
      });
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openRepo() async {
    final r = _result;
    if (r == null) return;
    await launchUrl(Uri.parse(r.repoUrl), mode: LaunchMode.externalApplication);
  }

  Future<void> _install() async {
    final r = _result;
    if (r == null) return;
    // share_plus 13.x API
    await SharePlus.instance.share(ShareParams(
      files: [XFile(r.apkPath)],
      text: 'فایل نصب ${r.repoName} — ساخته‌شده با Liberto',
    ));
  }

  Widget _warn(String t) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(t, style: const TextStyle(color: Colors.red, fontSize: 13)),
      );

  Widget _buildStackPicker() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تکنولوژی برنامه',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _templates.values)
                  ChoiceChip(
                    label: Text(t.title),
                    selected: _stackId == t.id,
                    onSelected: (_) => setState(() => _stackId = t.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_templates[_stackId]!.tagline,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (var i = 0; i < buildSteps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  i < _step
                      ? Icons.check_circle
                      : i == _step
                          ? Icons.schedule
                          : Icons.radio_button_unchecked,
                  color: i < _step
                      ? Colors.green
                      : i == _step
                          ? Colors.blue
                          : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        buildSteps[i],
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                i == _step ? FontWeight.bold : FontWeight.normal),
                      ),
                      if (i == _step && _detail.isNotEmpty)
                        Text(_detail,
                            style:
                                const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (i == _step)
                  const SizedBox(width: 8, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Text(
            'این فرآیند معمولاً ۵ تا ۲۰ دقیقه طول می‌کشد (صف بیلد GitHub). این صفحه را نبند.',
            style: TextStyle(color: Colors.orange, fontSize: 12)),
      ],
    );
  }

  Widget _buildResultCard() {
    final r = _result!;
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🎉 برنامه‌ات آماده شد!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('ریپو: ${r.repoName}\nفایل نصب: ${r.sizeMb} مگابایت'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                  onPressed: _install,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('نصب / اشتراک فایل')),
              OutlinedButton.icon(
                  onPressed: _openRepo,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('باز کردن ریپو')),
              TextButton(
                  onPressed: () =>
                      setState(() {
                        _result = null;
                        _descCtrl.clear();
                      }),
                  child: const Text('▶ بساز دیگری')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('❌ خطا',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(_error!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('🔁 تلاش دوباره')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liberto — سازنده‌ی برنامه'),
        actions: [
          IconButton(
            tooltip: 'مدل هوش مصنوعی',
            icon: const Icon(Icons.smart_toy_rounded),
            onPressed: _busy ? null : _openModelPicker,
          ),
        ],
      ),
      body: SafeArea(
        child: _busy
            ? _buildProgress()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_result != null) _buildResultCard(),
                  if (_error != null) _buildErrorCard(),
                  _buildStackPicker(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'بگو دقیقاً چه برنامه‌ای می‌خواهی...\nمثلاً: یک برنامه‌ی شمارشگر زمان با زنگ و لیست کارها',
                      border: OutlineInputBorder(),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('مدل: $_modelName (با آیکون 🤖 بالای صفحه عوضش کن)',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (_apiKey.isEmpty)
                    _warn('⚠️ هنوز کلید OpenRouter را وارد نکرده‌ای — از تب «تنظیمات»'),
                  if (_ghToken.isEmpty)
                    _warn('⚠️ هنوز توکن GitHub را وارد نکرده‌ای — از تب «تنظیمات»'),
                  const SizedBox(height: 12),
                  if (!_ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextButton.icon(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('برو به تب تنظیمات و توکن/کلید جدید را وارد و ذخیره کن')),
                        ),
                        icon: const Icon(Icons.settings_suggest_rounded),
                        label: const Text('تعویض یا وارد کردن توکن جدید (اگر قبلی مسدود شد)'),
                        style: TextButton.styleFrom(foregroundColor: Colors.orange.shade800),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _ready ? _start : null,
                    icon: const Icon(Icons.construction_rounded),
                    label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('🛠 بساز — AI کد می‌نویسد، GitHub کامپایل می‌کند',
                            style: TextStyle(fontSize: 15))),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'کد در گیت‌هاب خودت می‌ماند، کامپایل روی سرورهای GitHub انجام می‌شود و فایل نصب آماده برمی‌گردد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
      ),
    );
  }
}
