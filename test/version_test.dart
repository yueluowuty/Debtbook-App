/// 版本号一致性。lib/app_info.dart 里的两个常量是手写的，
/// 界面上要显示它、JSON 快照元数据也要写它，一旦和 pubspec.yaml 漂移，
/// 用户看到的就是一个不存在的版本 —— 所以把漂移变成测试失败。
library;

import 'dart:io';

import 'package:debtbook/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kAppVersion / kAppBuild 与 pubspec.yaml 的 version 一致', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'pubspec.yaml 里找不到 version: 行');

    final raw = line.substring('version:'.length).trim();
    final parts = raw.split('+');

    expect(kAppVersion, parts[0],
        reason: 'pubspec 是 $raw，改 version 时要同步改 lib/app_info.dart');
    expect(kAppBuild, parts.length > 1 ? parts[1] : '1',
        reason: '构建号是 + 后面那段，同样要同步');
  });
}
