import 'package:debtbook/data/updater.dart';
import 'package:debtbook/db/repo.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
