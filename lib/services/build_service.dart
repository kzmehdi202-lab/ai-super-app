import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_templates.dart';
import 'code_generator.dart';
import 'github_service.dart';

class BuildResult {
  BuildResult({
    required this.apkPath,
    required this.repoUrl,
    required this.repoName,
    required this.sizeBytes,
  });

  final String apkPath;
  final String repoUrl;
  final String repoName;
  final int sizeBytes;

  String get sizeMb => (sizeBytes / 1048576).toStringAsFixed(1);
}

/// Steps shown in the UI (Persian).
const List<String> buildSteps = [
  'بررسی توکن GitHub',
  'هوش مصنوعی کد را می‌نویسد',
  'ساخت ریپو',
  'ارسال فایل‌ها',
  'کامپایل روی سرورهای GitHub',
  'دریافت فایل نصب',
];

/// Orchestrates: AI code generation -> push to GitHub -> wait for Actions
/// build -> download the APK artifact.
class BuildService {
  Future<BuildResult> build({
    required String apiKey,
    required String model,
    required String ghToken,
    required StackTemplate template,
    required String description,
    void Function(int step, String detail)? onProgress,
  }) async {
    void p(int i, String d) => onProgress?.call(i, d);
    final gh = GitHubService();

    p(0, '...');
    final login = await gh.verifyToken(ghToken);

    p(1, 'مدل: $model');
    final project = await CodeGenerator.generate(
      apiKey: apiKey,
      model: model,
      template: template,
      description: description,
    );

    final now = DateTime.now().toUtc();
    final ts =
        '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final repoName = 'liberto-${project.slug}-$ts';

    p(2, 'اسم ریپو: $repoName');
    await gh.createRepo(ghToken, repoName,
        description: '${project.appName} — Built with Liberto');

    p(3, '${project.files.length} فایل');
    await gh.pushAllFiles(ghToken, login, repoName, project.files);

    p(4, 'در انتظار شروع بیلد...');
    ActionRun? firstRun;
    var waited = 0;
    while (waited < 240) {
      await Future<void>.delayed(const Duration(seconds: 10));
      waited += 10;
      final r = await gh.latestRun(ghToken, login, repoName);
      if (r != null) {
        firstRun = r;
        break;
      }
    }
    if (firstRun == null) {
      throw GitHubError(
          'بیلد شروع نشد — شاید چند دقیقه وقت ببرد، از ریپو دوباره امتحان کن: https://github.com/$login/$repoName/actions');
    }

    p(4, 'بیلد در حال اجرا است...');
    var current = firstRun;
    var w2 = 0;
    while (current.status != 'completed' && w2 < 1500) {
      await Future<void>.delayed(const Duration(seconds: 15));
      w2 += 15;
      final r = await gh.latestRun(ghToken, login, repoName);
      if (r != null) current = r;
    }
    if (current.status != 'completed' || current.conclusion != 'success') {
      throw GitHubError(
          'کامپایل شکست یا خیلی طول کشید — لاگ بیلد را از اینجا ببین: https://github.com/$login/$repoName/actions');
    }

    p(5, '...');
    final arts = await gh.listArtifacts(ghToken, login, repoName, current.id);
    if (arts.isEmpty) {
      throw GitHubError('فایلی از بیلد به دست نیامد');
    }
    final artId = arts.first['id'] as int;
    final dir = await getTemporaryDirectory();
    final apkPath = '${dir.path}/$repoName.apk';
    await gh.downloadApkArtifact(ghToken, login, repoName, artId, apkPath);

    final f = File(apkPath);
    if (!f.existsSync() || f.lengthSync() == 0) {
      throw GitHubError('دریافت فایل نصب شکست — دوباره امتحان کن');
    }

    return BuildResult(
      apkPath: apkPath,
      repoUrl: 'https://github.com/$login/$repoName',
      repoName: repoName,
      sizeBytes: f.lengthSync(),
    );
  }
}
