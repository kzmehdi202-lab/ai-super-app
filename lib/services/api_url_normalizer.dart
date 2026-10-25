/// Deterministic repair of API addresses in AI-generated code.
///
/// The model keeps inventing hosts/paths that do not exist
/// (api.openrouter.ai, api.github.com/api/v3, github.com/api/repos,
/// api.livepeer.studio/api/ai, ...). Those builds fail at runtime with
/// 404/401 and the user is told "my token is wrong".
///
/// This rewrites the known-broken forms to the real endpoints and reports
/// what it changed, so the builder can say what it fixed instead of
/// silently shipping broken code.
class ApiUrlFix {
  final String label;
  final int count;
  ApiUrlFix(this.label, this.count);
}

class ApiUrlResult {
  final String code;
  final List<ApiUrlFix> fixes;
  final List<String> stillSuspicious;
  ApiUrlResult(this.code, this.fixes, this.stillSuspicious);

  int get fixCount => fixes.fold(0, (a, b) => a + b.count);
  bool get hasIssues => stillSuspicious.isNotEmpty;
}

class _Rule {
  final RegExp pattern;
  final String replacement;
  final String label;
  _Rule(this.pattern, this.replacement, this.label);
}

class ApiUrlNormalizer {
  static final List<_Rule> _rules = [
    _Rule(RegExp(r'api\.openrouter\.ai', caseSensitive: false),
        'openrouter.ai', 'host اشتباه → openrouter.ai'),
    _Rule(RegExp(r'openrouter\.ai/api/v1/api/v1', caseSensitive: false),
        'openrouter.ai/api/v1', 'مسیر تکراری /api/v1'),
    _Rule(RegExp(r'openrouter\.ai/api/v1/v1\b', caseSensitive: false),
        'openrouter.ai/api/v1', 'مسیر تکراری /v1'),
    _Rule(RegExp(r'api\.github\.com/api/v3', caseSensitive: false),
        'api.github.com', 'حذف /api/v3'),
    _Rule(RegExp(r'api\.github\.com/v3\b', caseSensitive: false),
        'api.github.com', 'حذف /v3'),
    _Rule(RegExp(r'github\.com/api/repos', caseSensitive: false),
        'api.github.com/repos', 'host → api.github.com'),
    _Rule(RegExp(r'github\.com/repos', caseSensitive: false),
        'api.github.com/repos', 'host → api.github.com'),
    _Rule(RegExp(r'api\.livepeer\.studio/api/ai', caseSensitive: false),
        'livepeer.studio/api/ai', 'host → livepeer.studio'),
    _Rule(RegExp(r'livepeer\.studio/api/ai/api/ai', caseSensitive: false),
        'livepeer.studio/api/ai', 'مسیر تکراری /api/ai'),
    _Rule(RegExp(r'livepeer\.studio/api/ai/video\b', caseSensitive: false),
        'livepeer.studio/api/ai/text-to-video', 'مسیر → text-to-video'),
    _Rule(RegExp(r'api\.openai\.com/v1/v1', caseSensitive: false),
        'api.openai.com/v1', 'مسیر /v1 تکراری'),
  ];

  static final List<_Rule> _suspicious = [
    _Rule(RegExp(r'api\.github\.com/api', caseSensitive: false), '', 'api.github.com/api'),
    _Rule(RegExp(r'github\.com/api/', caseSensitive: false), '', 'github.com/api/'),
    _Rule(RegExp(r'openrouter\.ai/api/v1/api', caseSensitive: false), '', 'openrouter.ai/api/v1/api'),
    _Rule(RegExp(r'openrouter\.ai/api/v\d', caseSensitive: false), '', 'openrouter.ai/api/vN'),
    _Rule(RegExp(r'livepeer\.studio/api/ai/api', caseSensitive: false), '', 'livepeer.studio/api/ai/api'),
    _Rule(RegExp(r'(?<![\w.])api\.livepeer\.studio', caseSensitive: false), '', 'api.livepeer.studio'),
    _Rule(RegExp(r'api\.v3\.', caseSensitive: false), '', 'api.v3.'),
  ];

  static bool isCode(String path) =>
      path.endsWith('.dart') ||
      path.endsWith('.js') ||
      path.endsWith('.ts') ||
      path.endsWith('.kt') ||
      path.endsWith('.kts') ||
      path.endsWith('.py') ||
      path.endsWith('.swift') ||
      path.endsWith('.java');

  /// Rewrites broken API addresses inside [code].
  static ApiUrlResult apply(String code) {
    final fixes = <ApiUrlFix>[];
    var out = code;

    for (final rule in _rules) {
      final n = rule.pattern.allMatches(out).length;
      if (n == 0) continue;
      out = out.replaceAll(rule.pattern, rule.replacement);
      fixes.add(ApiUrlFix(rule.label, n));
    }

    // https://host//path → https://host/path
    final dupSlash = RegExp(r'''(https?://[^\s"'`]+?)(/{2,})''');
    if (dupSlash.hasMatch(out)) {
      out = out.replaceAllMapped(dupSlash, (m) => '${m.group(1)}/');
      fixes.add(ApiUrlFix('اسلش تکراری در URL', 1));
    }

    // missing scheme for known hosts
    final noScheme = RegExp(
        r'''(?<![:/])(?<!//)\b(openrouter\.ai/api/v1|api\.github\.com|livepeer\.studio/api/ai)''');
    if (noScheme.hasMatch(out)) {
      out = out.replaceAllMapped(noScheme, (m) => 'https://${m.group(1)}');
      fixes.add(ApiUrlFix('scheme جا افتاده → https://', 1));
    }

    final suspicious = <String>[];
    for (final rule in _suspicious) {
      if (rule.pattern.hasMatch(out)) suspicious.add(rule.label);
    }
    return ApiUrlResult(out, fixes, suspicious);
  }
}
