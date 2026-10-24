import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/github_service.dart';
import '../services/liberto_source.dart';
import '../services/native_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _systemCtrl = TextEditingController();
  final TextEditingController _ghUserCtrl = TextEditingController();
  final TextEditingController _ghTokenCtrl = TextEditingController();
  final TextEditingController _glUserCtrl = TextEditingController();
  final TextEditingController _glTokenCtrl = TextEditingController();
  final TextEditingController _voiceServerCtrl = TextEditingController();
  final TextEditingController _lpKeyCtrl = TextEditingController();
  final TextEditingController _universalKeyCtrl = TextEditingController();
  String _detectedPlatform = '';
  String _detectedStoreKey = '';
  String _universalStatus = '';
  List<Map<String, String>> _ring = [];
  bool _obscure = true;
  bool _ghObscure = true;
  bool _glObscure = true;
  bool _lpObscure = true;
  bool _loaded = false;
  bool _uncensored = true;
  String _fingerprint = '';
  String? _ghStatus;
  bool _ghOk = false;
  bool _ghTesting = false;
  bool _selfPushing = false;
  String? _selfPushMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final key = await NativeService.getApiKey();
      final system = await NativeService.getSetting('system_prompt');

      // بدون مقدار هاردکد: فیلدها دقیقاً همان چیزی را نشان می‌دهند که
      // ذخیره شده. خالی = واقعاً خالی. پر/حذف/جایگزینی فقط با اقدام کاربر.
      _keyCtrl.text = key;
      _systemCtrl.text = system;

      _ghUserCtrl.text = await NativeService.getSetting('github_user');
      _ghTokenCtrl.text = await NativeService.getSetting('github_token');

      _glUserCtrl.text = await NativeService.getSetting('gitlab_user');
      _glTokenCtrl.text = await NativeService.getSetting('gitlab_token');

      _voiceServerCtrl.text = await NativeService.getSetting('voice_server_url');

      _lpKeyCtrl.text = await NativeService.getSetting('livepeer_key');

      try {
        final rawRing = await NativeService.getSetting('token_ring');
        if (rawRing.isNotEmpty) {
          final list = jsonDecode(rawRing) as List;
          _ring = list
              .map((e) => Map<String, String>.from((e as Map).map(
                  (k, v) => MapEntry(k.toString(), v.toString()))))
              .toList();
        }
      } catch (_) {
        _ring = [];
      }
      
      if (_keyCtrl.text.isNotEmpty) {
        try {
          _fingerprint = await NativeService.nativeSha256(_keyCtrl.text);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Settings _load error: $e');
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _detectAndApplyUniversalKey(String val) {
    final t = val.trim();
    if (t.isEmpty) {
      setState(() {
        _detectedPlatform = '';
        _detectedStoreKey = '';
        _universalStatus = '';
      });
      return;
    }
    String plat = 'سایر / عمومی';
    String storeKey = 'custom_api_key';
    if (t.startsWith('ghp_') || t.startsWith('github_pat_')) {
      plat = 'GitHub Token';
      storeKey = 'github_token';
      _ghTokenCtrl.text = t;
    } else if (t.startsWith('sk-or-')) {
      plat = 'OpenRouter API Key';
      storeKey = 'openrouter';
      _keyCtrl.text = t;
    } else if (t.startsWith('hf_')) {
      plat = 'HuggingFace Token';
      storeKey = 'huggingface_key';
      NativeService.saveSetting('huggingface_key', t);
    } else if (t.startsWith('AIzaSy')) {
      plat = 'Google / Gemini API Key';
      storeKey = 'google_key';
      NativeService.saveSetting('google_key', t);
    } else if (t.startsWith('glpat-')) {
      plat = 'GitLab Token';
      storeKey = 'gitlab_token';
      _glTokenCtrl.text = t;
    } else if (t.contains('-') && t.length >= 32) {
      plat = 'Livepeer / UUID Key';
      storeKey = 'livepeer_key';
      _lpKeyCtrl.text = t;
    } else if (t.startsWith('gsk_')) {
      plat = 'Groq API Key';
      storeKey = 'groq_key';
      NativeService.saveSetting('groq_key', t);
    } else if (t.startsWith('r8_')) {
      plat = 'Replicate API Key';
      storeKey = 'replicate_key';
      NativeService.saveSetting('replicate_key', t);
    } else {
      plat = 'کلید عمومی / Grandmind / سفارشی';
      storeKey = 'custom_api_key';
      NativeService.saveSetting('custom_api_key', t);
    }
    setState(() {
      _detectedPlatform = plat;
      _detectedStoreKey = storeKey;
      _universalStatus = 'شناسایی شد: $plat — دکمه ✓ برای افزودن به لیست کلیدها';
    });
  }

  Future<void> _commitUniversalKey() async {
    final t = _universalKeyCtrl.text.trim();
    if (t.isEmpty) {
      setState(() => _universalStatus = '⚠️ اول کلید را در کادر بنویسید');
      return;
    }
    _detectAndApplyUniversalKey(t);
    final masked = t.length > 10
        ? '${t.substring(0, 6)}…${t.substring(t.length - 4)}'
        : t;
    final already = _ring.any((e) => e['masked'] == masked);
    if (!already) {
      setState(() => _ring.add({
        'name': _detectedPlatform.isEmpty ? 'کلید' : _detectedPlatform,
        'masked': masked,
        'key': _detectedStoreKey,
      }));
    }
    await NativeService.saveSetting('token_ring', jsonEncode(_ring));
    _universalKeyCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(already ? 'این کلید قبلاً در لیست است' : 'کلید اضافه و ذخیره شد ✓')),
      );
    }
    setState(() => _universalStatus = '');
  }

  Future<void> _removeRing(int i) async {
    if (i < 0 || i >= _ring.length) return;
    final k = _ring[i]['key'] ?? '';
    if (k == 'openrouter') {
      await NativeService.deleteApiKey();
      _keyCtrl.clear();
      _fingerprint = '';
    } else if (k == 'github_token') {
      _ghTokenCtrl.clear();
      await NativeService.saveSetting('github_token', '');
    } else if (k == 'gitlab_token') {
      _glTokenCtrl.clear();
      await NativeService.saveSetting('gitlab_token', '');
    } else if (k == 'livepeer_key') {
      _lpKeyCtrl.clear();
      await NativeService.saveSetting('livepeer_key', '');
    } else if (k.isNotEmpty) {
      await NativeService.saveSetting(k, '');
    }
    setState(() => _ring.removeAt(i));
    await NativeService.saveSetting('token_ring', jsonEncode(_ring));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کلید حذف شد ✕')),
      );
    }
  }

  Future<void> _moveRing(int i, int d) async {
    final j = i + d;
    if (i < 0 || j < 0 || j >= _ring.length) return;
    setState(() {
      final e = _ring.removeAt(i);
      _ring.insert(j, e);
    });
    await NativeService.saveSetting('token_ring', jsonEncode(_ring));
  }

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isNotEmpty) {
      await NativeService.saveApiKey(key);
      _fingerprint = await NativeService.nativeSha256(key);
    } else {
      await NativeService.deleteApiKey();
      _fingerprint = '';
    }
    await NativeService.saveSetting('system_prompt', _systemCtrl.text.trim());
    await NativeService.saveSetting('uncensored', _uncensored ? '1' : '0');
    await NativeService.saveSetting('voice_server_url', _voiceServerCtrl.text.trim());
    await NativeService.saveSetting('livepeer_key', _lpKeyCtrl.text.trim());
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ذخیره شد ✓')),
      );
    }
  }

  void _deleteKey() async {
    await NativeService.deleteApiKey();
    _keyCtrl.clear();
    _fingerprint = '';
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کلید حذف شد')),
    );
  }

  Future<void> _saveGithub() async {
    await NativeService.saveSetting('github_user', _ghUserCtrl.text.trim());
    await NativeService.saveSetting('github_token', _ghTokenCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات GitHub ذخیره شد ✓')),
      );
    }
  }

  Future<void> _testGithub() async {
    setState(() {
      _ghTesting = true;
      _ghStatus = null;
      _ghOk = false;
    });
    try {
      final login = await GitHubService().verifyToken(_ghTokenCtrl.text.trim());
      if (mounted) {
        setState(() {
          _ghOk = true;
          _ghStatus = '✓ متصل شد به حساب: $login';
          _ghTesting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ghOk = false;
          _ghStatus = e.toString();
          _ghTesting = false;
        });
      }
    }
  }

  Future<void> _saveGitlab() async {
    await NativeService.saveSetting('gitlab_user', _glUserCtrl.text.trim());
    await NativeService.saveSetting('gitlab_token', _glTokenCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات GitLab ذخیره شد ✓')),
      );
    }
  }

  /// Pushes Liberto's own source to the user's GitHub (repo: liberto).
  /// GitHub Actions then builds the Liberto APK in the cloud.
  Future<void> _selfPush() async {
    if (_ghUserCtrl.text.trim().isEmpty || _ghTokenCtrl.text.trim().isEmpty) {
      setState(() => _selfPushMsg = 'اول یوزر و توکن GitHub را وارد و ذخیره کن');
      return;
    }
    setState(() {
      _selfPushing = true;
      _selfPushMsg = 'اتصال به GitHub...';
    });
    try {
      await _saveGithub();
      final gh = GitHubService();
      final token = _ghTokenCtrl.text.trim();
      final login = await gh.verifyToken(token);
      if (mounted) setState(() => _selfPushMsg = 'ساخت ریپوی liberto...');
      await gh.createRepo(token, 'liberto',
          description: 'Liberto — AI Android app builder (source)');
      if (mounted) {
        setState(() => _selfPushMsg = 'ارسال ${libertoSource.length} فایل...');
      }
      await gh.pushAllFiles(token, login, 'liberto', libertoSource);
      if (mounted) {
        setState(() => _selfPushMsg =
            '✅ تموم شد! ریپو: https://github.com/$login/liberto — بیلد ابری شروع شده؛ فایل نصب Liberto به‌عنوان artifact در همان ریپو آماده می‌شود.');
      }
    } catch (e) {
      if (mounted) setState(() => _selfPushMsg = '❌ ${e.toString()}');
    } finally {
      if (mounted) setState(() => _selfPushing = false);
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _systemCtrl.dispose();
    _ghUserCtrl.dispose();
    _ghTokenCtrl.dispose();
    _glUserCtrl.dispose();
    _glTokenCtrl.dispose();
    _lpKeyCtrl.dispose();
    _universalKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 2,
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('ورودی هوشمند کلیدها (Universal Key Ring)',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'هر کلیدی (GitHub, Google, HuggingFace, OpenRouter, Grandmind و...) داری اینجا پیست کن، برنامه خودش نوعش رو تشخیص میده و ست میکنه.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _universalKeyCtrl,
                    onChanged: _detectAndApplyUniversalKey,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'هر توکن یا کلیدی را اینجا وارد کن...',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: _commitUniversalKey,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_universalStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _universalStatus,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (_ring.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('کلیدهای ذخیره‌شده:',
                        style: theme.textTheme.labelLarge),
                    ..._ring.asMap().entries.map((en) {
                      final i = en.key;
                      final e = en.value;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(e['name'] ?? 'کلید',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text(e['masked'] ?? '',
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 16),
                              tooltip: 'بالا',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _moveRing(i, -1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 16),
                              tooltip: 'پایین',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _moveRing(i, 1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.deepOrange),
                              tooltip: 'حذف کامل',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _removeRing(i),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('کلید API OpenRouter',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'sk-or-v1-…',
                      helperText: 'از openrouter.ai/keys می‌گیری',
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_fingerprint.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.fingerprint,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'SHA-256 (محاسبه در C++): ${_fingerprint.substring(0, 16)}…',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _keyCtrl.text.isEmpty ? null : _deleteKey,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف کلید'),
                      style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('GitHub', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'برنامه‌ساز با این توکن کد اپ‌های تو را روی GitHub می‌گذارد و آنجا کامپایل می‌کند.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ghUserCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'یوزرنیم GitHub',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ghTokenCtrl,
                    obscureText: _ghObscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'توکن GitHub (ghp_...)',
                      suffixIcon: IconButton(
                        icon: Icon(_ghObscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _ghObscure = !_ghObscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveGithub,
                          child: const Text('ذخیره'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _ghTesting ? null : _testGithub,
                          child: _ghTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('آزمایش اتصال'),
                        ),
                      ),
                    ],
                  ),
                  if (_ghStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _ghStatus!,
                        style: TextStyle(
                            fontSize: 13,
                            color: _ghOk ? Colors.green : Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('GitLab', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'اگر حساب GitLab هم داری، توکنش را اینجا بگذار — در نسخه‌ی بعدی، برنامه‌ساز روی GitLab هم بیلد می‌زند. الان ذخیره می‌شود و آماده است.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _glUserCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'یوزر GitLab',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _glTokenCtrl,
                    obscureText: _glObscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'توکن GitLab (glpat-...)',
                      suffixIcon: IconButton(
                        icon: Icon(_glObscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _glObscure = !_glObscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _saveGitlab,
                    child: const Text('ذخیره GitLab'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.video_library, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('تنظیمات Livepeer (ویدیو)', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'کلید API برای تولید ویدیو از متن (Text-to-Video).',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lpKeyCtrl,
                    obscureText: _lpObscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'Livepeer API Key',
                      suffixIcon: IconButton(
                        icon: Icon(_lpObscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _lpObscure = !_lpObscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_voice, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('سرور هوش مصنوعی صوتی (محلی)', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'آدرس IP کامپیوتری که سرور پایتون روی آن اجرا می‌شود را اینجا وارد کن.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceServerCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'http://192.168.1.100:8000',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('کد خودِ Liberto',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'کد کامل همین برنامه (Flutter + Kotlin + C++) را در ریپوی liberto روی حساب خودت می‌گذارد؛ GitHub خودش بیلد می‌کند و فایل نصب Liberto را در آن ریپو آماده می‌کند — لینک دائمی.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _selfPushing ? null : _selfPush,
                    icon: _selfPushing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_rounded),
                    label: const Text('بفرست به GitHub من'),
                  ),
                  if (_selfPushMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(_selfPushMsg!,
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('دستور شخصی (اختیاری)',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _systemCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          'مثلا‌ً: همیشه به فارسی جواب بده و کوتاه جواب بده…',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: SwitchListTile(
              value: _uncensored,
              onChanged: (v) => setState(() => _uncensored = v),
              title: const Text('حالت بدون سانسور'),
              subtitle: const Text(
                  'برای همه بخش‌ها (چت و سازنده): بدون رد کردن، بدون مقدمه‌چینی'),
              secondary:
                  Icon(Icons.lock_open, color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره تنظیمات'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}
