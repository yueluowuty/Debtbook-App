/// App 自更新：查 GitHub Releases 的 latest 版本，下载 APK 后交给系统安装器。
///
/// 这是全 App 唯一的出网路径，且只在用户手动点「检查更新」时发生。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../db/repo.dart';

const String kUpdateRepo = 'yueluowuty/Debtbook-App';

/// 下载目录名（docsDir 下），与 exports/backups 平级。
const String kUpdatesDirName = 'updates';

/// 手动下载兜底页面。
const String kReleasePageUrl = 'https://github.com/$kUpdateRepo/releases';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.apkBytes,
    required this.notes,
  });

  /// 不带 v 前缀的语义化版本，如 '1.0.1'。
  final String version;
  final String apkUrl;
  final int apkBytes;
  final String notes;
}

List<int> _verParts(String v) {
  final core = v.startsWith('v') ? v.substring(1) : v;
  return core.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

/// 语义化版本比较，长度不齐按 0 补（'1.1' == '1.1.0'）。
int compareVersions(String a, String b) {
  final pa = _verParts(a), pb = _verParts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va > vb ? 1 : -1;
  }
  return 0;
}

/// 从 Releases API 的 JSON 里取出版本与 APK 资产；没有 APK 资产返回 null。
UpdateInfo? parseLatestRelease(Object? decoded, {required String currentVersion}) {
  if (decoded is! Map) {
    throw const LedgerFailure('更新源返回了意外的 JSON 结构');
  }
  final map = decoded.cast<String, Object?>();
  final tag = map['tag_name'];
  if (tag is! String) return null; // 404 / 非对象：视为没有发布版本
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (compareVersions(version, currentVersion) <= 0) return null;

  final assets = (map['assets'] as List? ?? const []).cast<Object?>();
  Map<String, Object?>? apk;
  for (final a in assets) {
    if (a is Map && a['name'] is String && (a['name'] as String).endsWith('.apk')) {
      apk = a.cast<String, Object?>();
      break;
    }
  }
  if (apk == null) {
    throw LedgerFailure('v$version 没有附带 APK，请到 $kReleasePageUrl 手动下载');
  }
  final am = apk;
  final url = am['browser_download_url'] as String?;
  if (url == null) {
    throw const LedgerFailure('APK 资产缺少下载地址');
  }
  final body = map['body'];
  var notes = body is String ? body.trim() : '';
  if (notes.length > 300) notes = '${notes.substring(0, 300)}…';
  final size = am['size'];
  return UpdateInfo(
    version: version,
    apkUrl: url,
    apkBytes: size is int ? size : 0,
    notes: notes,
  );
}

/// 查询 latest release。当前已是最新（或没有更新版）时返回 null。
Future<UpdateInfo?> checkLatest({
  http.Client? client,
  required String currentVersion,
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(
      Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw LedgerFailure('更新源响应异常（HTTP ${res.statusCode}）');
    }
    return parseLatestRelease(jsonDecode(res.body), currentVersion: currentVersion);
  } on SocketException {
    throw const LedgerFailure('连不上 GitHub，请检查网络后重试');
  } on TimeoutException {
    throw const LedgerFailure('连 GitHub 超时，请稍后重试');
  } finally {
    if (client == null) c.close();
  }
}

/// 流式下载 APK 到 docsDir/updates/，回调 0..1 进度；返回落盘文件。
Future<File> downloadApk(
  UpdateInfo info,
  String docsDir, {
  required void Function(double fraction) onProgress,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', Uri.parse(info.apkUrl));
    final res = await c.send(req);
    if (res.statusCode >= 400) {
      throw LedgerFailure('下载失败（HTTP ${res.statusCode}）');
    }
    final dir = Directory(p.join(docsDir, kUpdatesDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'debtbook_v${info.version}.apk'));
    if (await file.exists()) await file.delete();

    final total = res.contentLength ?? info.apkBytes;
    final sink = file.openWrite();
    var done = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) onProgress(done / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total > 0 && done != total) {
      throw const LedgerFailure('下载不完整，请重试');
    }
    onProgress(1);
    return file;
  } on SocketException {
    throw const LedgerFailure('下载中断：连不上 GitHub，请重试');
  } finally {
    if (client == null) c.close();
  }
}
