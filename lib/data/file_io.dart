/// 导出/导入用到的文件读写。全部函数都接收一个 docsDir，
/// 这样同一套代码能在单测里指向临时目录，不需要设备。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/helper.dart';
import '../db/repo.dart';
import '../domain/snapshot.dart';

const String kExportsDirName = 'exports';
const String kBackupsDirName = 'backups';

/// 自动备份只保留最近这么多份。再多就是占用户空间了，
/// 真要长期留档应该导出手动备份并自己存走。
const int kMaxAutoBackups = 5;

/// 文件名里的时间戳。字典序即时间序，排序与裁剪都靠它，不用改文件属性。
String fileStamp([DateTime? now]) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
}

Future<Directory> _ensureDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<File> _dumpSnapshot(
  LedgerRepo repo,
  Directory dir,
  String fileName, {
  required String appVersion,
}) async {
  final snapshot = buildSnapshot(
    contacts: await repo.dumpTable(kTableContacts),
    bills: await repo.dumpTable(kTableBills),
    transactions: await repo.dumpTable(kTableTransactions),
    appVersion: appVersion,
    exportedAt: DateTime.now().toIso8601String(),
  );
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(encodeSnapshot(snapshot), flush: true);
  return file;
}

/// 导出 JSON 快照，返回落盘路径。
Future<File> writeSnapshotExport(
  LedgerRepo repo,
  String docsDir, {
  required String appVersion,
  String? fileName,
}) async {
  final dir = await _ensureDir(p.join(docsDir, kExportsDirName));
  return _dumpSnapshot(repo, dir, fileName ?? 'debtbook_${fileStamp()}.json',
      appVersion: appVersion);
}

/// 导入前把当前库原样备份一份，并把超出保留数的旧备份删掉。
Future<File> writeAutoBackup(
  LedgerRepo repo,
  String docsDir, {
  required String appVersion,
}) async {
  final dir = await _ensureDir(p.join(docsDir, kBackupsDirName));
  final file =
      await _dumpSnapshot(repo, dir, 'auto_${fileStamp()}.json', appVersion: appVersion);
  await pruneAutoBackups(docsDir);
  return file;
}

Future<List<File>> listAutoBackups(String docsDir) async {
  final dir = Directory(p.join(docsDir, kBackupsDirName));
  if (!await dir.exists()) return const [];
  final entries = <File>[];
  await for (final e in dir.list()) {
    if (e is File && p.basename(e.path).startsWith('auto_') && e.path.endsWith('.json')) {
      entries.add(e);
    }
  }
  // 文件名内嵌时间戳，倒序即「最新在前」。
  entries.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
  return entries;
}

/// 只裁剪 auto_ 前缀的文件，用户手动另存的备份绝不误删。
Future<int> pruneAutoBackups(String docsDir) async {
  final backups = await listAutoBackups(docsDir);
  var removed = 0;
  for (final f in backups.skip(kMaxAutoBackups)) {
    try {
      await f.delete();
      removed++;
    } on FileSystemException {
      // 正被别的进程占用（比如刚分享出去）就留到下次，不影响本次导入。
    }
  }
  return removed;
}

/// 读入用户选中的文件。内容校验交给 validateSnapshot，这里只管取字节。
Future<Map<String, Object?>> readSnapshotFileBytes(Uint8List bytes) async {
  try {
    return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  } on FormatException catch (e) {
    throw LedgerFailure('文件不是合法的 JSON：${e.message}');
  } on TypeError {
    throw const LedgerFailure('文件顶层不是 JSON 对象，不像本 App 导出的快照');
  }
}
