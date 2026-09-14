import 'dart:async';
import 'dart:io';

import 'package:debtbook/data/updater.dart';
import 'package:debtbook/db/repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _release({
  required String tag,
  bool withApk = true,
  String body = 'notes',
}) => {
      'tag_name': tag,
      'body': body,
      'assets': [
        if (withApk)
          {
            'name': 'app-release.apk',
            'size': 12345678,
            'browser_download_url': 'https://example.com/app.apk',
          },
        {'name': 'changelog.txt', 'size': 10},
      ],
    };

void main() {
  group('compareVersions', () {
    test('按数值而非字典序比较', () {
      expect(compareVersions('1.9.0', '1.10.0'), -1);
      expect(compareVersions('v2.0.0', '1.99.99'), 1);
      expect(compareVersions('1.1', '1.1.0'), 0);
    });
    test('忽略 +build 后缀', () {
      expect(compareVersions('1.0.0+2', '1.0.0+9'), 0);
    });
  });

  group('parseLatestRelease', () {
    test('有更新版时返回版本与 APK 直链', () {
      final info = parseLatestRelease(
        _release(tag: 'v1.2.0'),
        currentVersion: '1.0.0',
      );
      expect(info, isNotNull);
      expect(info!.version, '1.2.0');
      expect(info.apkUrl, 'https://example.com/app.apk');
      expect(info.apkBytes, 12345678);
    });

    test('同版本或更旧返回 null（不调 error）', () {
      expect(
          parseLatestRelease(_release(tag: 'v1.0.0'), currentVersion: '1.0.0'),
          isNull);
      expect(
          parseLatestRelease(_release(tag: 'v0.9.1'), currentVersion: '1.0.0'),
          isNull);
    });

    test('没有 tag（404 响应体）返回 null', () {
      expect(parseLatestRelease({'message': 'Not Found'}, currentVersion: '1.0.0'),
          isNull);
    });

    test('新版没有 APK 资产时报错并提示手动下载', () {
      expect(
        () => parseLatestRelease(_release(tag: 'v2.0.0', withApk: false),
            currentVersion: '1.0.0'),
        throwsA(isA<LedgerFailure>().having(
            (e) => e.message, 'message', contains(kReleasePageUrl))),
      );
    });

    test('超长发布说明截断', () {
      final info = parseLatestRelease(
        _release(tag: 'v1.1.0', body: 'x' * 500),
        currentVersion: '1.0.0',
      );
      expect(info!.notes.length, 301); // 300 字符 + 省略号
      expect(info.notes, endsWith('…'));
    });
  });

  group('downloadApk 断点续传', () {
    final bytes = List.generate(100, (i) => i);
    final info = UpdateInfo(
      version: '9.9.9',
      apkUrl: 'https://example.com/a.apk',
      apkBytes: 100,
      notes: '',
    );

    test('中途断流后重试，带 Range 从已落盘字节续传', () async {
      final ranges = <String?>[];
      var calls = 0;
      final client = MockClient.streaming((req, _) async {
        calls++;
        ranges.add(req.headers['range']);
        if (calls == 1) {
          final ctl = StreamController<List<int>>();
          // ignore: unawaited_futures
          Future.microtask(() {
            ctl.add(bytes.sublist(0, 40));
            ctl.addError(const SocketException('切后台被掐断'));
            ctl.close();
          });
          return http.StreamedResponse(ctl.stream, 200,
              contentLength: 100, request: req);
        }
        final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(ranges.last!)!.group(1)!);
        return http.StreamedResponse(
          Stream.value(bytes.sublist(start)),
          206,
          contentLength: bytes.length - start,
          request: req,
        );
      });
      final dir = await Directory.systemTemp.createTemp('debtbook_dl');
      addTearDown(() => dir.delete(recursive: true));

      final file = await downloadApk(info,
          onProgress: (_) {}, client: client, baseDir: dir);

      expect(await file.length(), 100);
      expect(await file.readAsBytes(), bytes);
      expect(ranges, [null, 'bytes=40-']);
      // .part 已改名转正，不残留
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('服务器不支持 Range（返回 200）时从头下载仍能完成', () async {
      final client = MockClient.streaming((req, _) async => http.StreamedResponse(
            Stream.value(bytes), 200, contentLength: 100, request: req));
      final dir = await Directory.systemTemp.createTemp('debtbook_dl');
      addTearDown(() => dir.delete(recursive: true));

      final file = await downloadApk(info,
          onProgress: (_) {}, client: client, baseDir: dir);
      expect(await file.readAsBytes(), bytes);
    });
  });
}
