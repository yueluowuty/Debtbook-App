/// App 版本。改 pubspec.yaml 的 `version:` 时同步改这里。
///
/// 没有引 package_info_plus 在运行时读：那要多一个平台插件，而这两行的一致性
/// 用 test/version_test.dart 断言就够了 —— 忘了改是测试变红，
/// 不是界面上悄悄显示一个过期版本号。
library;

/// 对应 pubspec `version:` 中 `+` 之前的部分，也是写进 JSON 快照元数据的值。
const String kAppVersion = '1.0.4';

/// 对应 `+` 之后的构建号。只用于界面展示，方便说清楚装的是哪一个包。
const String kAppBuild = '5';
