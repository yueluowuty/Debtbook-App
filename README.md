# 欠款台账（debtbook）

记录「谁欠我多少钱 / 我欠谁多少钱 / 什么时候还了多少」的本地记账 App。
纯离线：数据只在这台手机的文件里，唯一的出网动作是用户在「备份与恢复」页
**手动点击**「检查更新」（GitHub Releases API + APK 直链），不点则零请求。

## 对应三条诉求

| 诉求 | 做法 |
|---|---|
| 按借款人查看欠款 | 首页人员列表：色块胶囊里就是完整人名，右侧一行净差金额与最近活动日期，可搜姓名或手机号，可按应收/应付分段筛选 |
| 离线备份与恢复 | **JSON 快照**导出/导入（唯一的恢复格式）；导入前自动备份当前库，保留最近 5 份 —— 只写盘、不在界面列出，要恢复那份就走「从文件导入」 |
| 起始借款 / 还款 / 再借款，自动更新账单 | 每个「账单」下逐笔记流水，账单的借款合计、已还合计、剩余**全部由流水重算**，界面上不存在手工改余额的入口 |

## 装 APK

**推荐渠道：GitHub Releases**（本仓库 `Releases` 页），例如 `debtbook_v1.0.1.apk`（约 53 MB，
三 ABI 合一的 release 包）。App 内「备份与恢复 → 版本更新」可直接检查并调起安装。
传到手机后直接点开安装，需要允许「安装未知来源应用」。

> ⚠️ release 包目前用 **debug key 签名**。将来若换正式 keystore，旧包必须先卸载（数据会丢，
> 先导出 JSON 快照再装新包）。仓库公开只是为匿名检查更新可用，APK 本身无保密需求。

根目录如果存在 `debtbook-debug.apk`，那是本地调试产物，可能过时，不要拿它当发布物。

### 构建

项目目录已迁到纯 ASCII 路径 `D:\projects\debtbook-app`，**直接在本仓库构建即可**：

```bash
D:/apps/flutter_windows_3.47.2-stable/flutter/bin/flutter.bat build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

历史背景：项目曾放在中文路径 `D:\projects\记账本app`，当时 AGP 拒绝非 ASCII 路径、
Kotlin `.tab` 缓存关不掉、`file_picker` 的 jni 模块在 NDK/CMake 下产不出 `libdartjni.so`，
所以曾靠一份 ASCII 镜像目录（`D:\projects\debtbook`，其 `lib` 是指回中文目录的 junction）构建。
2026-09-12 起目录已改名去中文，镜像废弃。`android/gradle.properties` 里
`android.overridePathCheck` / `kotlin.incremental` 两个历史开关已无必要，留着无害。

## 在电脑上预览（Android 模拟器）

不用真机也能跑起来看，实测可用。

```bash
# 一次性：装模拟器与镜像（已经装好了）
D:/Android/sdk/cmdline-tools/latest/bin/sdkmanager.bat --sdk_root=D:/Android/sdk \
  "emulator" "system-images;android-36;google_apis;x86_64"
D:/Android/sdk/cmdline-tools/latest/bin/avdmanager.bat create avd -n debtbook \
  -k "system-images;android-36;google_apis;x86_64" -d pixel_7 --force

# 每次预览：窗口保持开着
D:/Android/sdk/emulator/emulator.exe -avd debtbook -gpu auto -no-snapshot-save
D:/Android/sdk/platform-tools/adb.exe wait-for-device
D:/Android/sdk/platform-tools/adb.exe install -r -g \
  /d/projects/debtbook-app/build/app/outputs/flutter-apk/app-debug.apk
D:/Android/sdk/platform-tools/adb.exe shell monkey -p com.lishuncai.debtbook \
  -c android.intent.category.LAUNCHER 1
```

AMD 平台只能走 WHPX，`emulator.exe -accel-check` 实测输出
`WHPX(10.0.26200) is installed and usable` —— 不用开 Hyper-V，不用重启。

关掉窗口再重开，App 数据完好（SQLite 在 AVD 的 userdata 里，`-no-snapshot-save`
只影响内存快照，实测热重启约 18 秒）。**别加 `-wipe-data`**，那会清空数据。

**两条路都能跑，用途不同**：只想看一眼就 `adb install` 现成 APK（完全绕开构建）；
要改代码就走下面那条热重载回路，或者直接在本目录 `flutter run`（ASCII 路径下构建是通的）。
debug 包里带 `lib/x86_64/libdartjni.so`，x86_64 镜像能跑。

两个不是 bug 的现象：

- 模拟器时区默认 GMT，界面上的日期会比北京时间少一天。源码里取日期全是
  `DateTime.now()`（本地时间），你手机 +08 上显示的是当天。
- `adb shell input text` 送中文会直接 NPE，只能送 ASCII；中文在窗口里用键盘手敲。

debug 包可以用 `run-as` 直接看私有目录，排查导出很有用：

```bash
D:/Android/sdk/platform-tools/adb.exe shell \
  "run-as com.lishuncai.debtbook ls -la ./app_flutter/exports"
```

## 开发回路：改代码自动热重载

```bash
# 1. 先把模拟器拉起来（窗口保持开着）
D:/Android/sdk/emulator/emulator.exe -avd debtbook -gpu host -no-snapshot-save

# 2. 起回路：构建 + 安装 + 启动，之后盯着 lib/ 改
python D:/projects/debtbook-app/tool/dev_run.py
```

改任意 `lib/**/*.dart` 存盘，约 0.5 秒后设备上就刷新（实测 `Reloaded 1 of 1714
libraries in 430~573ms`）。几条不显然的前提：

1. 构建就在本仓库做。目录曾改名去中文（见上文「历史背景」），
   旧镜像目录 `D:\projects\debtbook` 已彻底废弃，不要再引用。
2. **热重载走的是 `flutter run --machine` 的 `app.restart`**。
   直接往 `flutter run` 的 stdin 灌字符 `r` 是没用的 —— 它检测到自己不在 TTY 上，
   根本不进交互模式。
3. **协议帧必须是 JSON 数组**：每行 `[{"id":1,"method":"..."}]`，
   和它输出给你的格式一致。发裸对象 `{"id":1,...}` 的表现是**完全静默**：
   没有任何回包、没有任何报错，看着像卡死。这个坑实测烧掉了两轮构建才定位到，
   当时误判成「`.bat` 吞了 stdin」，其实换成直连 `dart.exe` 一样不回包。

回路只热重载 Dart 代码。改了 `pubspec.yaml`、原生代码或加了新文件，
得 Ctrl+C 重新起（`--full` 参数改用 hot restart）。

视觉验收用的小工具（与产品代码无关）：`tool/devrun/seed.sql` 往模拟器
数据库灌一批「文字很多」的测试数据，`tool/devrun/shots/` 是历次验收截图
（不进版本库）。

## 备份纪律（重要）

数据只在本机，**卸载 App 即全部丢失**，手机坏了也找不回来。建议：

1. 每次记完账，进「数据」页导出一次 JSON 快照，分享到微信收藏 / 网盘 / 电脑任意一处；
2. 换机或重装前，先导出一次，再在新机器上导入；
3. 导出的 JSON 可以自己用文本编辑器打开看，字段名就是数据库列名。

导入前生成的自动备份只存在应用私有目录，**跟着 App 一起消失**，界面上也不再列出。
它防的是「误导入错文件」，不防手机丢失或卸载；真要用它救数据，得把那个目录里的
`auto_*.json` 取出来，再走一次「从文件导入」。

## 算账口径（三条不可妥协）

1. **金额一律以「分」为整数存储与计算**，界面输入元、两位小数。全项目没有任何 double 参与金额运算。
2. **账单的 `principal_cents` / `payment_cents` / `balance_cents` 是派生值**，每次流水增删改都在
   同一个数据库事务里用 `SUM` 重算回写。所以「已结清的账单又新增一笔借款」天然成立，无需特殊分支。
3. **硬删除，不做软删**。没有 `isDeleted` 标记，避免污染每一条聚合查询。

结清状态不落库，`balance_cents == 0` 即结清；余额为负表示超付（对方多给了 / 我多付了）。

## 配色与排版

上一版只有 `ColorScheme.fromSeed(绿)`，后果是 surface 也被染成薄荷绿，
所有卡片都是「透明底 + 一圈灰线」，而一行里挤着四行同字重的文字 ——
用户原话是「色彩太素了，文字一多起来就看起来有点乱」。

现在整套视觉规则在 `lib/ui/theme.dart`，取舍如下：

- **底色回到中性**，颜色只留给五件语义事：应收（绿）、应付（橙）、已结清（灰）、
  危险操作（红）、信息说明（蓝）。由 `LedgerPalette` 这个 `ThemeExtension` 承载，
  界面里取 `LedgerPalette.of(context)`，不直接写 `Colors.xxx`。
- **层级靠底色块与字重拉开，不靠描边**。白卡给一条发丝描边，着色卡不给。
- 首页顶部是一整块渐变横幅（不再是 AppBar），净差金额是全屏唯一的特大字。
  横幅压着状态栏，所以它自己用 `AnnotatedRegion<SystemUiOverlayStyle>`
  把状态栏图标要成白色 —— 深色图标压在深绿上，时间和电量是看不见的。
- 所有文字样式都带 `FontFeature.tabularFigures()`，金额列逐位对齐。
- 列表行里的说明性文字压成 `MetaLine`（`Text.rich` 用 ` · ` 连接，能正常折行）、
  `AmountTag`、`ToneBadge` 和左侧色条，不再用整句描述。
  首页借款人行的「N 个账单 · N 笔流水」已经去掉：左列只有半张卡宽，
  三个数字必然折行，折在「5 笔\n流水」中间比少一个数字更难读。
- 方向选择用 `ToneChoice` 而不是 `SegmentedButton` —— 后者无法给单个分段着色，
  而「应收绿 / 应付橙」正是这一版最需要被看见的区别。

**右对齐的金额必须用 `Expanded`，不能用 `Flexible`。**
`Expanded` 和 `Flexible` 的默认 `flex` 都是 1，一行里同时出现两者时可用空间一律 50/50 分；
区别只在于 `Flexible` 给的是上限、不要求填满，于是内容宽度小于自己那半个槽位，
`crossAxisAlignment.end` 对齐到的是**槽位起点**而不是卡片右边缘 ——
金额胶囊就没贴右，而且每行的右空隙还随金额长短不一样。
也不能退回非 flex 孩子：`Row` 给非 flex 孩子无限宽主约束，里面的 `FittedBox` 永远不会缩放。
首页借款人行与 `TxRow` 都栽过这同一条。

- 人员页的「全部流水」默认收起（`SectionHeader` 支持 `onTap` + `expanded`）。
  一个人几十笔流水时，账单列表会被整段顶出屏幕，而进这一页九成是看账单。
- 人员页在账单模块上方有一条归还进度。
  **只算一侧**：应收侧的「已还」是他还我，应付侧的「已还」是我还他，
  两边混成一个比值没有意义，所以取借款额更大的那侧单独算并在标题里写明。
  超付时进度条画满，但百分比照实写 120%，不藏。
- App 版本在「备份与恢复」页底部展示（`v1.0.1（build 2）`）。
  值手写在 `lib/app_info.dart`，由 `test/version_test.dart` 断言它和 `pubspec.yaml`
  的 `version:` 一致 —— 忘了同步是测试变红，而不是界面上显示一个不存在的版本。

## 金额展示规则

存储与计算永远是精确到分的整数，**只有界面显示会按需压缩**：

| 位置 | 显示 | 例子 |
| --- | --- | --- |
| 首页横幅的净差与两块小计、借款人行的金额、人员页顶部小计、人员页账单行的「剩余」、账单页大号余额 | 满 1 万转「万」，满 1 亿转「亿」，保留两位小数并去掉末尾的 0 | `¥1.5万`、`¥12.35万`、`¥1,234.57万`、`¥1.23亿` |
| 账单页「累计借出 / 已还」两张小卡、导入预览的应收应付合计、流水列表每一行、JSON 快照 | 精确到分的千分位，一个子不省；空间不够时整串等比缩小 | `¥12,345.00` |
| 不足 1 万的任何金额 | 与精确格式完全相同 | `¥200.00` |

账单页与导入预览那两处刻意不压缩 —— 它们是核对备份/导出用的，精确值比省字重要，
所以宁可让字变小也不改数。

压缩只发生在 `formatCentsCompact()`（`lib/domain/money.dart`），全程整数运算、
最后一步才四舍五入到万/亿的第二位小数，不参与任何累加。
真机上金额一长就把布局撑乱，是这个函数加上 `FittedBox(fit: BoxFit.scaleDown)` 一起治的 ——
**缩放而不是截断**，界面上不允许出现 `¥1,500....` 这种省略号金额。
一整串数字没有断行机会（`¥1,234,567.89` 是不可拆的一整块），所以任何可能放不下的大号金额
都必须包 `FittedBox`，否则就是横向溢出。

措辞统一：结清一律叫「已结清」（不叫「两讫」，这个词太书面）；
首页横幅只留净差数字本身，不再挂那颗按符号给的「可收回 / 待偿还」说明胶囊 —— 正负号已经说了同一件事。
借款人行上的「已结清」照旧。

## 导入语义

单机使用，**导入 = 全量覆盖**，不按 id 合并。流程固定为：

选文件 → 校验（列出全部问题后中止） → 预览条数与合计 → 自动备份当前库 → 单事务覆盖写入。

校验会拦下：id 缺失/重复/非正整数、`bill_id` 与 `contact_id` 悬空、金额非正整数、
`kind` / `direction` 非法、日期不是 `YYYY-MM-DD`、`schemaVersion` 高于当前 App。
账单的三个派生金额列**不信任文件**，一律按文件里的流水重算，与文件值不符只提示不阻断。

## v1 明确不支持的操作

不是做不出来，是为了避免静默算错：

- **改已有流水账单的方向**：`in`/`out` 一换，`principal` 与 `payment` 的含义整体反转，等于把账算反。
- **删除仍有流水的账单**：会让流水悬空。先逐笔删流水，或删掉整个借款人（连带删除，有二次确认）。
- **账单合并 / 拆分**。

允许：把一笔流水挪到**同方向**的另一个账单（弹二次确认，新旧两个账单都会重算）。

## 开发环境

这个项目绑定 **Flutter 3.47.2 / Dart 3.13.2**，装在
`D:\apps\flutter_windows_3.47.2-stable\flutter`，全局 PATH 也已指向它
（2026-09-15 清掉了旧的 3.22.2）。下文仍写绝对路径，是为了不受终端 PATH 影响：

```bash
D:/apps/flutter_windows_3.47.2-stable/flutter/bin/flutter.bat test
D:/apps/flutter_windows_3.47.2-stable/flutter/bin/flutter.bat build apk --debug
```

国内镜像（本机直连 `storage.googleapis.com` 不通）：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

### 跑测试需要仓库根目录的 sqlite3.dll

`package:sqlite3` 的 build hook 默认从 GitHub Releases 下预编译 dll，本机取不到，
因此 `pubspec.yaml` 里改成按裸名加载系统库：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: sqlite3
```

配套要在**仓库根目录**放一个自包含的 64 位 `sqlite3.dll`（`flutter test` 的工作目录就是项目根，
正常库搜索顺序能找到它）。这份 dll 已加进 `.gitignore`，不进版本库，
可以从任意 Python 发行版的 `DLLs/sqlite3.dll` 复制。
（Git for Windows 自带的 `msys-sqlite3-0.dll` 依赖 msys-2.0.dll，单独复制过去会在
`sqlite3_initialize` 直接崩，别用。）

这个 dll **只服务于测试**，不参与 APK 构建 —— 安卓上 sqflite 用的是原生插件自带的 SQLite。

### 用 `dart analyze` 而不是 `flutter analyze`

`flutter analyze` 曾在中文路径下崩溃（flutter_tools 计算 LSP 的 `Content-Length` 时按字符数而非字节数）。
目录已改 ASCII 名，理论上一半前提消失，但未回归验证过；`dart analyze` 结果等价且一直稳定，继续用它。

```bash
D:/apps/flutter_windows_3.47.2-stable/flutter/bin/dart.bat analyze
```

## 目录结构

```
lib/
  main.dart                  # 启动时开库 + 加载首页
  app_info.dart              # 写进快照元数据的版本号，改 pubspec 时同步
  db/
    helper.dart              # 建库、升级、onConfigure 开外键
    repo.dart                # 全部读写与 recomputeBills
  domain/                    # 纯 Dart，不 import flutter，可脱离设备单测
    money.dart               # 元 <-> 分
    models.dart              # 实体、显示口径、asIntOrNull / asExactInt
    snapshot.dart            # 快照生成 + 「派生列由流水算」的纯 Dart 口径
    validate.dart            # 导入校验与归一化
  data/file_io.dart          # 导出落盘、自动备份与保留裁剪
  data/updater.dart          # 检查更新：GitHub Releases 查询 / 版本比较 / APK 流式下载
  state/store.dart           # ChangeNotifier + InheritedNotifier
  ui/                        # home / person / bill / tx / contact / data / widgets
```

`domain/` 下不允许出现任何 Flutter 代码 —— 这是「没有手机也能把算账逻辑全验完」的前提。
状态管理刻意没引 riverpod，一个 `ChangeNotifier` 加 `revision` 计数就够，
少一个在没有设备时无法调试的依赖。

## 测试

```bash
D:/apps/flutter_windows_3.47.2-stable/flutter/bin/flutter.bat test
```

117 个用例，跑在**真实 SQLite** 上（`sqflite_common_ffi`），覆盖：
库级约束、派生列重算（含跨账单挪流水、超付负数、SQL 与纯 Dart 两种实现互相对拍）、
汇总查询、v1 业务禁令、全量覆盖导入（含导出→导入→再导出的逐字节往返）、
金额解析格式化与万/亿压缩显示、快照校验器每条规则的负例、日期的点分显示口径，
另有 10 条 widget 冒烟用例（首页渲染、空状态、添加借款人的完整点击链路、
表单校验、金额千分位与万/亿压缩、方向筛选、长金额不许被省略号截断、放大系统字号不溢出、
人名只在色块胶囊里出现一次且长名不撑破行、流水行金额贴右且第二行整宽）。

冒烟用例已经抓到过三个真实界面缺陷（统计条 `stretch` 撞无限高导致整棵树报错、
12px 溢出、以及写死 92 高在大字号下溢出），这类问题 `dart analyze` 是看不见的。
但**空账本抓不到「金额一长就被省略号截成 `¥1,500....`」** —— 那是模拟器里记了一笔
¥1,500.00 之后才看见的。所以那条用例特意把测试窗口设成模拟器的 411dp 宽
（1080px / 2.625 dpr）并造了一笔大额流水，再用 `RenderParagraph.didExceedMaxLines` 断言；
去掉 `FittedBox` 它会变红，不是空转。

前两条用例都测不到「92 高写死」这个 bug，因为**模拟器字号偏小而用户手机开了大字号**，
所以补了 `textScaleFactorTestValue = 1.6` 这一条。它的反证同样做过：
把 `IntrinsicHeight` 临时换回 `SizedBox(height: 92)`，这条立刻变红。
同理，写断言前逐个查过 Flutter 源码确认 `BoxFit.scaleDown` 会按文字自然宽度测量
（`RenderFittedBox.performLayout` 用 `parentUsesSize: true` 布局子节点），
以及 `RenderParagraph.didExceedMaxLines` 的语义确实是「是否被截断」。

冒烟用例的 `pump()` 现在显式传 `theme: buildDebtBookTheme()`。跑默认主题的话，
这一版的语义色、字号层级和 `LedgerPalette` 这个 `ThemeExtension` 全都不在覆盖范围内 ——
主题文件里任何一处写错，测试仍然是全绿的。

**冒烟用例的能力边界**：`testWidgets` 跑在 FakeAsync 里，而 sqflite 的 ffi 实现走
真实 isolate，所以**页面 `initState` 里发起的加载在 widget 测试中永远完不成**
—— PersonPage / BillPage 的「加载后界面」测不了，它们的算账正确性由
`test/repo_test.dart` 在真实 SQLite 上覆盖。

## 已验证 / 未验证

**已验证（`flutter test` + `dart analyze`）**：全部算账逻辑、约束、导入校验、CSV 编码。

**已验证（Android 16 / x86_64 模拟器上实跑 debug APK）**：

- 五屏渲染、中文排版、三块统计卡不溢出；SQLite 文件在 `app_flutter/` 私有目录读写正常；
  顺带抓到并修掉两处只有真机渲染才暴露的缺陷 —— 底部提示行缺 `SafeArea` 被手势条压住一半、
  统计卡金额一长就被省略号截断；
- **导入**走的是真 SAF：`documentsui/.picker.PickActivity` 弹起 → 选 Downloads 里的文件 →
  读出字节 → 校验 → 弹出「导入 4 条记录？」预览（来源文件名、三类计数、应收应付、覆盖警告）→
  「备份并导入」→ 数据正确，且自动生成并列出 `auto_*.json` 与「回滚」按钮；
- **导出**走的是系统 share sheet：JSON 显示 "Sharing 1 file" 带正确文件名，
  CSV 显示 "Sharing 3 files"；文件同时落在 `app_flutter/exports/` 与 `cache/share_plus/`；
- 派生金额端到端正确：借出 2000 + 还款 500 → `principal_cents 200000 /
  payment_cents 50000 / balance_cents 150000`，界面 ¥1,500.00；
- CSV 字节级确认：开头 `EF BB BF`（BOM）、行尾 `\r\n`（CRLF），Excel 可直接打开。

**清单声明的权限**（v1.0.1 起写进 **main** manifest，debug/release 都有）：
`INTERNET` 与 `REQUEST_INSTALL_PACKAGES`，两条都只服务「检查更新 → 下载 APK → 调起系统安装器」
这一条手动路径；另有 AndroidX 自动加的 `com.lishuncai.debtbook.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
（自己 uid 内的广播保护，不是对外权限）。**仍然没有任何存储权限、没有 MANAGE_EXTERNAL_STORAGE**，
备份导入导出一律走 SAF 与 share sheet。

**还需要你在真机上确认**：share sheet 选微信时对方能不能正常收到文件（模拟器没装微信），
以及点击手感和输入法习惯。

### 本轮真机验收反馈的三处修复，各自的验证到哪一层

| 修复 | 已验证 |
| --- | --- |
| 首页满屏红色 `BOTTOM OVERFLOWED` 小字 | 统计条写死的 92 高改为 `IntrinsicHeight` 等高；`textScaleFactorTestValue = 1.6` 用例通过，且把高度写回 92 会立刻变红（反证过） |
| 「两讫」措辞 | 全部改为「已结清」，净差卡按符号显示「可收回 / 待偿还 / 已结清」；CSV 人员表状态列同步，`csv_test` 断言到新值 |
| 长金额撑乱布局 + 改用「万」 | `formatCentsCompact` 5 条单测；首页统计卡 `didExceedMaxLines` 用例；`dart analyze` 干净 |

**模拟器逐屏复查**（`font_scale 1.6`，真实记了一笔 `12,345,678.90`）：
首页、人员页、账单页、数据页、记账面板五屏都过了一遍，
大号金额显示为 `¥1,234.72万`，同一行的明细与流水保持精确的 `¥12,347,678.90`，
派生算式（借出 12,345,678.90 + 2,000.00 − 还款 500.00）三处数字互相对得上。

这一轮在设备上**又抓到两处同类溢出**，都是测试和 `dart analyze` 看不见的：

- **借款人列表行溢出 6px**。根因不是写死高度，而是 `ListTile` 给 `trailing` 的
  `maxHeight` 恒为 **56 逻辑像素**（`maxIconHeightConstraint`），既不随行高也不随字号变化，
  而那里放的是两行文字。反证方式：给自定义 Row 的 trailing 临时套一个 `SizedBox(height: 56)`，
  字号放大用例立刻报 `RenderFlex overflowed by 2.0 pixels on the bottom`。
  之前那条字号用例是**空账本**跑的，ListView 一行都没有，所以完全测不到这里。
- **人员页账单行横向溢出 6.6px**。根因是 `Row` 给非 flex 子节点的是**无限宽主约束**，
  「借出 … · 已还 … · N 笔」那行永远不会换行，只能顶穿卡片。改成上下两行各占满宽。

一条踩过的排查弯路，记下来避免重犯：**靠 `grep` 日志找溢出是假阴性**。
人员页那处溢出当时在 `dev_run.log` 和 `logcat` 里都 grep 不到任何 overflow，
差点当成已通过 —— 截图上那条黄黑 `RIGHT OVERFLOWED BY 6.6 PIXELS` 才是事实。
布局问题只有眼睛看画面这一道关，日志不可靠。

安卓侧 `AndroidManifest.xml` **不声明任何存储权限**，全走 SAF 与 share sheet，
所以导入读的是选择器返回的文件字节，不拼 content URI 路径。
`allowedExtensions` 在部分安卓文件管理器上不生效、仍可任选文件 —— 反正最终由内容校验兜底。

## 界面简化这一轮（去冗余信息与功能），各自的验证到哪一层

删掉的入口：备份与恢复页的「当前数据」统计、「导出 3 份 CSV 报表」、自动备份列表与
「回滚」、「危险操作 / 清空全部数据」；首页净差旁的「可收回 / 待偿还」胶囊；
借款人行的名字与「x 笔流水」；账单卡的「应收/应付」胶囊与「x 笔」。
界面改动：人名改由色块胶囊完整承载（宽度自适应）；账单卡的「+」换成「记一笔」按钮；
流水行改为两行 —— 第一行「类型/账单名 + 右上角金额」，第二行整宽「时间 · 渠道 · 备注」；
全 App 日期显示统一为 `yyyy.MM.dd`（`formatDateDot`，存储仍是 ISO）。

| 改动 | 已验证 | 还差 |
| --- | --- | --- |
| 删掉的 4 个入口及其服务层（`csv_report.dart`、`writeCsvExports`/`dayIso`、`clearEverything`） | `dart analyze` 干净（`unused_element` / `unused_local_variable` 是 warning 级、默认致命，私有方法漏删会红）；但这几个都是 public，漏删不报错 → 已按符号名 grep 过 `lib/` `test/` 零命中 | — |
| 人名胶囊只出现一次、9 字名 + 归档徽标 + 手机号 + 六位金额在 411dp / 1.6 字号不溢出 | 新增 widget 用例（`findsOneWidget` + `takeException isNull`）通过 | 真机上「每行色块宽度不同、左边缘参差」是否顺眼 |
| 流水行两行式、金额贴右 | 新增 widget 用例直接 pump `TxRow`：金额槽右边缘 == 行右边缘 − 12，且金额顶边在第二行之上 | 人员页 / 账单页在 widget test 里 pump 不起来（见本文件开头第 2 条），两屏只能眼看 |
| 日期 `yyyy.MM.dd` | `formatDateDot` 单测（含前导零、非法输入原样返回）；首页「最近 2026.09.01」由用例锁定；`lib/` 里 `substring(5)` 已归零 | 记账面板「改日期 → 保存 → 重开」的往返：显示出去的串绝不能被反解回存储 |

`flutter test` 117 条全绿。**上表「还差」那一列必须装 APK 补**：本轮三处改动全是布局，
而本文件已经记过两次「测试和 `dart analyze` 都看不见、只有截图看得见」的溢出，
且 `grep` 日志找 overflow 给过假阴性 —— 眼看这一道关省不掉。

**眼看这道关当场抓到一个**：1.6 倍系统字号下，人名胶囊比原来定宽 44 的头像占地方，
手机号那半个槽位被挤窄，11 位号码折成「1381234567 / 8」两截。
`dart analyze` 看不见，`takeException` 也看不见 —— **折行不抛异常**。
修法是号码整块 `FittedBox(scaleDown)`，不许折行；并补了一条断言把这件事钉住：
量手机号那一行的渲染高度必须 `< 30`（`bodySmall` 在 1.6 倍下约 25 高）。
反证过：把 `FittedBox` 摘掉，这条量到 108、立刻变红。

### 紧接的第二轮界面微调（同一批截图里改的）

- **人名胶囊改成固定字号 + 最多 5 个字**：`PersonAvatar` 去掉 `FittedBox`，改 `maxChars`
  按缩放后的字号算宽度、超出走省略号 —— 之前长名字是被无声缩到看不清的。
  列表里所有人于是同一个字号；**人员详情页顶栏不适用**（全名只有那一处落点，`maxWidth: 220`）。
- **已归档单独成组**：行内「已归档」徽标删掉（它要吃掉一小截宽度），归档的人排在主列表**上方**，
  组前一行「已归档 N 人」小标；搜索行那个开关保留，关时整组不见。
- **账单卡色条改身份色**：`billBarHues`（青/蓝/紫/玫红四个）+ `billBarHueSeed(title)`，
  同一个人的账单再撞色就往后挪一格（`_PersonPageState._barColors`）。
- **可折叠小节标题去掉点击时的水波纹**（`SectionHeader` 的 splash/highlight 设透明），
  点「全部流水」时标题后面不再糊出一块灰底；反馈交给那个旋转箭头。

第二轮同样是**只有眼看才抓到**的一个问题：色条最初直接复用了人名那套 `_avatarHues`，
而它八个色里含 `0B7A52`（就是应收绿）与 `B45309`（就是应付橙）再加两个绿系 ——
王志强两张应收账单的色条于是撞成同一种绿，「按账单区分」当场失效。
所以另起了四个远离语义色的色相，并加了同组避让。

### 紧接着的第三轮（还是界面细节）

- **胶囊里的字上下居中**：`SizedBox` 定了高，但里面的 `Text` 一直是贴在上沿的。
  换 `Column(mainAxisAlignment: center)` 而不是 `Center` —— 后者会把自己撑到
  `maxWidth`，每个胶囊都变成同一个最宽块，「随名字自适应」直接失效。
- **归档行整块淡底**：`archivedTint`（`DCE4EC`）。先用 `neutralSoft`（`EAEFF4`）实测
  只比页面底暗 20 个级差，在列表里根本分不出「这是另一拨」，而分出来正是这一组唯一的目的。
- **账单第一笔的色条恒用主题深绿**：它永远在最上面，颜色不变反而成了一个锚；
  身份色只负责区分第二笔往后是哪一单。
- 顺带修掉一个只有装到机器上才看得见的 bug：`PersonAvatar` 里 168 那道宽度天花板
  本该只兜「按屏宽算」的默认值，却把调用方显式传的 `maxWidth: 220` 也夹掉了 ——
  详情页 9 字的名字因此被截成「王志强（老家表…」。
