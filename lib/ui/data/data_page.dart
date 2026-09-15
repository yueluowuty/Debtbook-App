import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app_info.dart';
import '../../data/file_io.dart';
import '../../data/updater.dart';
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store = StoreScope.read(context);
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

  // ------------------------------------------------------------- 检查更新

  static const _updateChannel =
      MethodChannel('com.lishuncai.debtbook/update');

  Future<void> _checkUpdate() => _guard(() async {
        final info = await checkLatest(currentVersion: kAppVersion);
        if (!mounted) return;
        if (info == null) {
          _toast('已是最新版本 v$kAppVersion');
          return;
        }
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('升级到 v${info.version}？'),
            content: _UpdatePanel(info: info),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('下载并安装')),
            ],
          ),
        );
        if (go != true) return;
        if (!Platform.isAndroid) {
          _toast('仅 Android 支持应用内安装，请从 $kReleasePageUrl 下载');
          return;
        }
        await _downloadAndInstall(info);
      });

  /// 下载期间顶一个进度对话框；完成后交给系统安装器。
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('下载 v${info.version}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (ctx, f, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: f),
              const SizedBox(height: 8),
              Text(
                '${(f * 100).clamp(0, 100).round()}%'
                '${info.apkBytes > 0 ? ' · 共 ${_humanBytes(info.apkBytes)}' : ''}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final file = await downloadApk(info,
          onProgress: (f) => progress.value = f);
      if (!mounted) return;
      Navigator.of(context).pop(); // 收掉进度对话框
      late final bool? ok;
      try {
        ok = await _updateChannel
            .invokeMethod<bool>('installApk', {'path': file.path});
      } on PlatformException catch (e) {
        _toast('未能调起系统安装器：${e.message ?? e.code}');
        return;
      }
      if (ok != true) {
        _toast('未能调起系统安装器，请到 $kReleasePageUrl 手动安装');
      } else {
        _toast('已调起安装器：装完即为 v${info.version}，数据不会丢');
      }
    } catch (_) {
      // 只可能是下载段抛的错；此时进度对话框还开着，先收掉再交给 _guard toast。
      if (mounted) Navigator.of(context).pop();
      rethrow;
    } finally {
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = LedgerPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32, top: 8),
        children: [
          _Section(
            title: '备份',
            accent: pal.info,
            child: _ActionTile(
              icon: Icons.download_outlined,
              tone: Tone.info,
              title: '导出 JSON 快照',
              subtitle: '完整数据，可用于恢复。每次记完账都建议导一份。',
              busy: _busy,
              onTap: _exportSnapshot,
            ),
          ),
          _Section(
            title: '恢复',
            accent: pal.receivable,
            child: _ActionTile(
              icon: Icons.upload_outlined,
              tone: Tone.receivable,
              title: '从文件导入',
              subtitle: '导入前会校验并预览，当前数据先自动备份。',
              busy: _busy,
              onTap: _pickAndImport,
            ),
          ),
          _Section(
            title: '版本更新',
            accent: pal.info,
            child: _ActionTile(
              icon: Icons.system_update_alt_outlined,
              tone: Tone.info,
              title: '从 GitHub 检查更新',
              subtitle: '对比 Releases 里的最新版本并下载安装包；只有点这里才会联网。',
              busy: _busy,
              onTap: _checkUpdate,
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
                      '本 App 不联网，所有数据只在手机本机'
                      '（上面「检查更新」是唯一例外，且只在点击时才发请求）。'
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

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.info});
  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('v$kAppVersion → v${info.version}',
            style: theme.textTheme.titleMedium),
        if (info.apkBytes > 0)
          MetaLine(gap: 4, parts: ['安装包 ${_humanBytes(info.apkBytes)}']),
        if (info.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(info.notes,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          ),
        ],
      ],
    );
  }
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
