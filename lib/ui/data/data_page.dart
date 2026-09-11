import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app_info.dart';
import '../../data/file_io.dart';
import '../../db/repo.dart';
import '../../domain/money.dart';
import '../../domain/validate.dart';
import '../../state/store.dart';
import '../theme.dart';
import '../widgets/ledger_widgets.dart';

/// 备份与恢复。导入是全库覆盖，本 App 唯一的毁灭性操作，
/// 所以路径固定为：校验 → 预览 → 自动备份 → 覆盖。
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  LedgerStore? _store;
  List<FileBackup> _backups = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final files = await listAutoBackups(_store!.docsDir);
    final backups = <FileBackup>[];
    for (final f in files) {
      backups.add(
        FileBackup(
          file: f,
          bytes: await f.length(),
          modified: await f.lastModified(),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _backups = backups);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on LedgerFailure catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _exportSnapshot() => _guard(() async {
    final file = await writeSnapshotExport(
      _store!.repo,
      _store!.docsDir,
      appVersion: kAppVersion,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        title: '导出记账快照',
        text: '欠款台账备份 ${fileStamp()}',
      ),
    );
    _toast('已导出并调起分享：${p.basename(file.path)}');
  });

  Future<void> _exportCsv() => _guard(() async {
    final files = await writeCsvExports(_store!.repo, _store!.docsDir);
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final f in files) XFile(f.path)],
        title: '导出对账报表',
      ),
    );
    _toast('已导出 ${files.length} 份 CSV');
  });

  // ------------------------------------------------------------- 导入

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择要导入的快照文件',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return;
    await _guard(() async {
      final decoded = await readSnapshotFileBytes(await picked.readAsBytes());
      await _importDecoded(decoded, sourceName: picked.name);
    });
  }

  Future<void> _importFromBackup(FileBackup b) async {
    await _guard(() async {
      final decoded = await readSnapshotFileBytes(await b.file.readAsBytes());
      await _importDecoded(decoded, sourceName: b.name);
    });
  }

  /// 校验 → 预览确认 → 自动备份 → 全量覆盖。
  Future<void> _importDecoded(
    Object? decoded, {
    required String sourceName,
  }) async {
    final store = _store!;
    final result = validateSnapshot(decoded);

    if (!result.ok) {
      if (mounted) await _showErrors(result);
      return;
    }
    final data = result.data!;
    if (!mounted) return;

    final pal = LedgerPalette.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导入 ${data.totalRows} 条记录？'),
        content: _PreviewPanel(data: data, sourceName: sourceName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('备份并导入'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final backup = await writeAutoBackup(
      store.repo,
      store.docsDir,
      appVersion: kAppVersion,
    );
    await store.repo.replaceAll(data);
    await store.reload();
    await _loadBackups();
    _toast('导入完成，覆盖前的数据已存为 ${p.basename(backup.path)}');
  }

  Future<void> _showErrors(SnapshotValidation v) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('文件校验未通过（${v.errorCount} 个问题）'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in v.errors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('· $e', style: const TextStyle(fontSize: 13)),
                ),
              if (v.tailHint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    v.tailHint,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('返回修改文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    final pal = LedgerPalette.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: const Text(
          '借款人、账单、流水全部删除，不可撤销。\n'
          '建议先导出一次备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _guard(() async {
      final store = _store!;
      await writeAutoBackup(store.repo, store.docsDir, appVersion: kAppVersion);
      await store.repo.clearEverything();
      await store.reload();
      await _loadBackups();
      _toast('已清空，清空前的数据已自动备份');
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final pal = LedgerPalette.of(context);
    final t = store.totals;

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32, top: 8),
        children: [
          _Section(
            title: '当前数据',
            accent: pal.info,
            child: TintedCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: _StatGrid([
                _Stat('借款人', '${store.contacts.length}'),
                _Stat(
                  '应收',
                  '¥${formatCents(t.receivableCents)}',
                  tone: Tone.receivable,
                ),
                _Stat(
                  '应付',
                  '¥${formatCents(t.payableCents)}',
                  tone: Tone.payable,
                ),
                if (store.archivedCount > 0)
                  _Stat('含归档', '${store.archivedCount}'),
              ]),
            ),
          ),
          _Section(
            title: '备份',
            accent: pal.info,
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.download_outlined,
                  tone: Tone.info,
                  title: '导出 JSON 快照',
                  subtitle: '完整数据，可用于恢复。每次记完账都建议导一份。',
                  busy: _busy,
                  onTap: _exportSnapshot,
                ),
                _ActionTile(
                  icon: Icons.table_chart_outlined,
                  tone: Tone.info,
                  title: '导出 3 份 CSV 报表',
                  subtitle: '流水明细 / 账单汇总 / 人员汇总，给 Excel 对账用，不能用来恢复。',
                  busy: _busy,
                  onTap: _exportCsv,
                ),
              ],
            ),
          ),
          _Section(
            title: '恢复',
            accent: pal.receivable,
            child: Column(
              children: [
                _ActionTile(
                  icon: Icons.upload_outlined,
                  tone: Tone.receivable,
                  title: '从文件导入',
                  subtitle: '导入前会校验并预览，当前数据先自动备份。',
                  busy: _busy,
                  onTap: _pickAndImport,
                ),
                if (_backups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Text(
                      '还没有自动备份。每次导入或清空前都会自动生成一份。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  TintedCard(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        for (final b in _backups)
                          ListTile(
                            leading: Icon(
                              Icons.history,
                              size: 20,
                              color: pal.meta,
                            ),
                            title: Text(
                              b.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_humanBytes(b.bytes)} · ${_fmtTime(b.modified)}',
                            ),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _importFromBackup(b),
                              child: const Text('回滚'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: '危险操作',
            accent: pal.danger,
            child: _ActionTile(
              icon: Icons.delete_forever_outlined,
              tone: Tone.danger,
              title: '清空全部数据',
              subtitle: '清空前同样会自动备份。',
              busy: _busy,
              onTap: _clearAll,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: TintedCard(
              tone: Tone.info,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 17, color: pal.info),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '本 App 不联网，所有数据只在手机本机。'
                      '换机或卸载前，务必先把 JSON 快照存到别处。',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: pal.info.withValues(alpha: .95)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Center(
              child: Text(
                '欠款台账 v$kAppVersion（build $kAppBuild）',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: pal.meta),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FileBackup {
  const FileBackup({
    required this.file,
    required this.bytes,
    required this.modified,
  });
  final File file;
  final int bytes;
  final DateTime modified;
  String get name => p.basename(file.path);
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.data, required this.sourceName});
  final SnapshotData data;
  final String sourceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = LedgerPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('来源：$sourceName', style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        MetaLine(
          parts: [
            '借款人 ${data.contacts.length}',
            '账单 ${data.bills.length}',
            '流水 ${data.transactions.length}',
          ],
          style: theme.textTheme.bodyMedium,
        ),
        MetaLine(
          gap: 4,
          parts: [
            '应收 ¥${formatCents(data.receivableCents)}',
            '应付 ¥${formatCents(data.payableCents)}',
          ],
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: pal.dangerSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 17, color: pal.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前手机上的全部数据都会被这个文件覆盖。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: pal.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (data.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final w in data.warnings)
            Text('提醒：$w', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.accent});
  final String title;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, accent: accent),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 两列网格。之前用的是 Wrap，但 Wrap 的格子宽度跟着内容走，
/// 落单的那一格会在右侧留一块不规则的空隙，看起来像没排完。
class _StatGrid extends StatelessWidget {
  const _StatGrid(this.stats);
  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < stats.length; i += 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: stats[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < stats.length
                      ? stats[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tone});
  final String label;
  final String value;
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = LedgerPalette.of(context);
    final t = tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t == null ? pal.neutralSoft : pal.soft(t),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: t == null ? pal.meta : pal.onSoft(t),
            ),
          ),
          const SizedBox(height: 1),
          // 这里刻意保留精确千分位（这是核对备份用的），但一整串数字没有断行机会，
          // 应收上千万时会顶破半宽的格子 —— 缩放而不是截断。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                color: t == null ? theme.colorScheme.onSurface : pal.ink(t),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = Tone.info,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Tone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TintedCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: busy ? null : onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                MetaLine(gap: 2, parts: [subtitle]),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
          ),
        ],
      ),
    );
  }
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _fmtTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.month}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
