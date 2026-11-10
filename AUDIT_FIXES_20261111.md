# 全项目审查与修复记录（2026-11-11）

本轮从 `main / 2ad49a3` 的干净工作区开始，确认并修复 **7 类产品问题**，同时修复 **1 类测试等待时序问题**，新增 13 个回归场景。重点包括教材习题记录正确性、异步操作与页面生命周期、通知失败状态、窄屏/大字布局和备份期间的主线程阻塞。

采用源码盘点、语义检索、关键调用链人工检查、全量静态分析、自动测试及故障复现。覆盖范围与未验证边界如下；不将自动检查通过等同于逐行正确性证明。

## 覆盖范围

[逐文件清单](AUDIT_SOURCE_INVENTORY_20261111.csv) 记录 964 个一方源码、测试及构建配置文件的路径、行数、修改前后 SHA-256、检查方法和人工重点。初始清单为 961 个，本轮新增 3 个测试文件。

| 范围 | 检查方式 |
|---|---|
| 应用 `lib/`：500 个 Dart 文件 | 全量静态分析、全量测试；重点读取存储/恢复、启动与路由、授权、通知、教材课程与习题、数学记录、首页统计与共用动效 |
| `test/`：369 → 372 个 Dart 文件 | 全量执行测试入口；包含辅助文件的数量不等于测试用例数 |
| `integration_test/`：12 个 Dart 文件 | 入口/隔离策略检查；本轮执行范围见验证结果 |
| `tools/`：53 个源码文件，`tool/`：1 个 | 诗词与教材 Dart 工具单独分析、内容校验、课程 CLI 回归；26 个 Python 文件 AST 检查及工具测试 |
| Android：16 个源码/配置；iOS：3 个源码/配置 | 配置盘点、Android API 24 一致性及 PDFium 原生依赖门禁；Android 模拟器验收 |
| 依赖与构建 | 锁定版本查询、项目/发布契约和工作流检查 |

源码清单不包含 Flutter SDK、第三方依赖源码、构建产物和 Trellis 运行时。内容资源通过对应加载、导入和校验链路检查。根目录分析排除了 `tools/**`，本轮另外分析诗词工具包和教材 CLI，未用应用分析结果代替工具检查。

| 领域 | 本轮核查重点 |
|---|---|
| 启动、路由、Hive、家长保护 | 初始化失败、缺失参数、授权代次、凭据隔离、销毁边界；已有恢复/权限回归纳入全量执行 |
| 备份、同步、图片与缓存 | 解密和预检先于写入、恢复屏障、内容迁移、损坏输入、加解密 CPU 工作与大图片快照 |
| 数学、诗词、学习统计 | 练习草稿和结算持久化、判分与历史、跨日窗口；数学 12 学期独立抽样 |
| 教材 | 单题审批、内容身份、课程替换、进度 revision、重复提交、连续操作、保存时离页 |
| 表达、助手、ASR/TTS | 既有生成/点评/取消/迟到回调及结算回归；原生播放器另做设备验收 |
| UI 与性能 | 320dp 窄屏、600dp 双列、2x 字号、深浅主题、设置项语义、历史列表懒构建、动效后台/离屏停止 |

## 已修复问题

P1 表示学习数据正确性风险，P2 表示功能、稳定性、布局或响应性能问题；未把未证实的攻击路径记为安全漏洞。

| 编号 | 等级 | 触发与影响 | 修复与回归证据 |
|---|---|---|---|
| A01 | P1 | 同 ID 习题被替换并重新审核后，旧页面仍可把旧答案写进新题的记录 | `recordAttempt` / `recordParentCheck` 必须传入所见题目的 `fingerprint`，仓储在课程锁内核对当前内容；旧摘要提交被拒绝且无记录写入 |
| A02 | P2 | 同帧连点或同时提交不同题目可重复进入保存；全书共享 revision 导致并发冲突；离页后继续访问 widget ref | 保存与家长核对弹窗共用同步互斥；保存期间全页提交禁用；衔接最近成功版本并在新快照加载后交还控制；await 后检查 mounted。延迟真实 Hive 写入验证仅一次提交、连续两题和保存中离页 |
| A03 | P2 | 通知权限等待时重复请求，页面离开后仍开启提醒；取消等异常未被 UI 接住 | 每日/周报/时间选择共用忙碌状态，权限返回检查生命周期，异常提示并允许重试；覆盖重复点击、权限期间离页和取消失败后重试 |
| A04 | P2 | 手动恢复通知后只清页面变量，持久降级标记仍在，重进误报失败；周报降级没有展示 | 每日与周报成功调度/取消时同步持久清标记，周报提供明确失败提示；验证存储读回及 UI 提示消失 |
| A05 | P2 | 通知设置的提醒时间和周报入口在 320dp、2x 字号下横向溢出 | 用共用 `AppTile` 和 `ColoredCard` 重排，文本可换行，补开关语义和保存反馈；验证可滚动且无布局异常 |
| A06 | P2 | 口算历史在 320dp 和 600dp 双列下统计/标题挤出，大字体加重 | 标题和统计改为 `Wrap`，列数考虑文字缩放，点击反馈交给 `ColoredCard`；4 组尺寸/字号均完整显示成绩、题数、时间，1000 条数据挂载数量仍小于 40 |
| A07 | P2 | 加解密函数虽为 async，JSON/Base64/PBKDF/AES 仍阻塞 UI isolate；大图片备份用例超时 | 将完整 cipher 操作移入只接收数据的 `Isolate.run`；不改备份格式、AAD、PBKDF 参数。保留错误口令、篡改、密钥失败、旧数据迁移和大图片完整恢复验证 |

对应主要实现：

- [习题仓储](lib/data/repositories/textbook_exercise_repository.dart)、[习题页面](lib/features/textbook/exercise/textbook_exercise_overview.dart)
- [通知服务](lib/core/services/notification_service.dart)、[通知设置](lib/features/profile/notification_settings_page.dart)
- [口算历史](lib/features/math/math_history_page.dart)、[备份加解密](lib/core/services/backup_payload_cipher.dart)

另修复 `practice_resume_test.dart` 的测试时序：原用例在提交后固定等待 300ms，再直接读取 `.values.single`，全量运行时持久化可能尚未完成，随后关闭 Hive 会影响下一个用例。现有界等待真实会话记录，排空写入后检查记录唯一性、答案和判定，没有通过放宽断言或增加全局超时掩盖问题。

## 性能证据

在本机 Dart VM 中，使用约 6 MiB 合成中文 JSON、固定合成设备密钥进行一次完整加密/解密，同时用 10ms 周期定时器观测主 isolate。结果内容完全一致。

| 指标 | 修复前 | 修复后 |
|---|---:|---:|
| 最长事件循环间隔 | 2073ms | 15ms |
| 定时器响应次数 | 3 | 119 |
| 整个探针耗时 | 2094ms | 1198ms |

这是同机功能探针，证明加解密不再长时间占住 UI 事件循环；不是 Android 帧率、低端机耗时或内存峰值结论。包含超过 32 MiB 真实 PNG 的备份定向回归约 19 秒通过。大备份仍采用整包格式，内存需求随内容大小增长，本轮没有宣称流式或恒定内存处理。

## 验证结果

基线静态分析通过。基线全量运行捕获大图片备份超时、竖式续练提前读取空记录和后续挂起；终止挂起 runner 后产生连带未完成错误，不能称为基线全量通过。

| 检查 | 结果 |
|---|---|
| 最终 Flutter 静态分析 | 通过，0 问题 |
| 最终全量 Flutter 测试 | **3777 通过，12 跳过，0 失败**；13 分 9 秒，concurrency=2 |
| Android 核心操作与音频解码 | **6 通过**；API 37 模拟器，独立 `com.poemath.app.integration` 包；debug 构建成功 |
| 改动页面截图检查 | 6 组真实中文字体截图已检查：320/390/600dp，1x/2x，深浅主题；无截字、重叠或横向溢出 |
| 数学独立抽样 | 12 学期 × 3000 = 36000 题；一致性、约束、括号整除错误均为 0 |
| 诗词资源校验 | 0 errors，0 warnings |
| 诗词工具包 / 教材 Dart CLI 分析 | 通过，0 问题 |
| Python AST | 26 个文件全部通过 |
| Python 项目/发布/安全工具测试 | 27 通过，另发布说明 4 通过 |
| PDF 导入器 | 锁定 requirements 的隔离 uv 环境，12 通过 |
| Android 版本契约 | API 24 五处一致 |
| PDFium / 项目契约 | 通过 |
| OSV 依赖查询 | 206 个 Pub 包版本、8 个 PyPI 包版本，返回漏洞记录 0 |
| `git diff --check` | 通过 |

依赖结果按当前锁文件的公开包名/版本调用 [OSV 批量查询接口](https://google.github.io/osv.dev/post-v1-querybatch/) 得到；它仅代表该数据库在本次查询时返回的已知记录，不覆盖未知漏洞或应用业务逻辑。原始查询结果和性能/测试日志摘要保留在本地任务的 `research/` 目录。

12 个跳过项均来自 `textbook_course_real_pdf_test.dart`：需显式提供
`TEXTBOOK_PDF_DIRECTORY` 和 `TEXTBOOK_PDFIUM_LIBRARY` 的 12 册真实教材整理
验收，本轮未提供这些输入。它们未计入通过数量。截图通过离屏 Flutter 渲染
生成，使用本地中文字体；Android 操作流程为另一项独立验收。

本地截图示例：[通知设置 320dp/2x](.trellis/tasks/11-11-comprehensive-quality-audit/research/notifications-320-2-light.png)、
[口算历史 320dp/2x 深色](.trellis/tasks/11-11-comprehensive-quality-audit/research/history-320-2-dark.png)、
[口算历史 600dp 双列](.trellis/tasks/11-11-comprehensive-quality-audit/research/history-600-1-light.png)。
这些截图与任务规范位于项目忽略的 `.trellis/`，可在本工作区查看；根目录审查
报告、逐文件清单及代码/回归测试随本轮按功能分批提交归档。

关键复跑命令：

```bash
~/.pub-cache/bin/fvm flutter analyze --no-pub
~/.pub-cache/bin/fvm flutter test --no-pub --concurrency=2 --reporter=json
~/.pub-cache/bin/fvm flutter test integration_test/app_journeys_test.dart -d emulator-5554 --dart-define=POEMATH_INTEGRATION_TEST=true --no-uninstall --no-pub
~/.pub-cache/bin/fvm dart run tools/bracket_audit.dart
~/.pub-cache/bin/fvm dart run tools/poem_importer/bin/poem_importer.dart validate
python3 tools/check_android_compatibility.py
python3 tools/check_pdfium_security.py
python3 tools/check_project_contracts.py
python3 -m unittest discover -s tools -p '*_test.py'
python3 tools/release_notes_test.py
uv run --no-project --with-requirements tools/textbook_importer/requirements.txt python -m unittest discover -s tools/textbook_importer/tests
git diff --check
```

## 验证边界

- 本轮未构建或运行 iOS，未在 Android API 24 真机及厂商定制系统上验证后台提醒、权限和电池优化行为。
- 云端请求使用项目现有模拟响应与协议回归，没有调用用户生产凭据或付费 API；公网服务可用性不在本轮结果内。
- 布局与主题检查覆盖自动场景及改动页面；不等于对所有设备、语言、字体或系统读屏组合完成验收。
- 不进行核心依赖升级、数据格式迁移或最低系统版本调整。普通学习与生产存储未被测试清理。

实现、回归和项目规范已同步。经用户确认，本轮改动已按教材习题、通知、口算历史、
备份性能、续练测试、审查文档六个批次提交，功能实现与对应回归测试在同一批次；
未推送或发布。提交前再次核对逐文件清单的 964 个 SHA-256 指纹，均与上述验收版本
一致；每批提交的暂存差异检查均通过。
