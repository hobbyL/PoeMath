# 全项目审查与修复记录（2026-11-08）

本轮从 `main / f03843b` 的干净工作区开始，确认并修复 **10 项代码缺陷**，另同步了本地隐私说明副本。新增 24 个测试用例。修复保留既有 Hive 字段编号、备份格式、Android API 24 和业务规则。

审查采用全库文件盘点、静态检查、风险模式定位、关键调用链人工分析、故障复现和回归测试。**这不是“每一行都已人工证明正确”或“项目已不存在任何漏洞”的声明。** 下文及逐文件清单区分了检查方式和未验证边界。

## 覆盖范围

[完整文件清单](AUDIT_SOURCE_INVENTORY_20261108.csv) 包含 905 个源码、测试及构建配置文件，记录路径、行数、SHA-256、检查方式、人工重点范围及风险模式命中数量。模式命中只是检索线索，不是漏洞数量。

| 范围 | 数量与检查方式 |
|---|---|
| 应用 `lib/` | 基线 478 个 Dart 文件、112333 行；修复后 479 个文件。全量 Flutter 静态分析及测试；重点人工追踪下表链路 |
| 测试 | `test/` 修复后 339 个 Dart 文件；`integration_test/` 11 个；`test_driver/` 1 个 |
| Dart 工具 | `tools/` 19 个 Dart 文件，`tool/` 1 个；导入器单独静态分析、资源校验、课程 CLI 测试及数学生成抽样 |
| Python 工具 | 21 个文件全部 AST 语法检查；安全/发布/项目契约测试及 PDF 导入器测试 |
| Android | 2 个 Kotlin 文件及 Manifest、备份规则、Gradle 等配置；debug 构建与 API 37 模拟器操作流程 |
| iOS | AppDelegate、Info.plist 及相关配置源码检查；本轮未构建或执行 iOS |
| 构建/依赖 | 3 个 GitHub 工作流、锁文件与配置检查；公开依赖漏洞数据库查询 |

清单覆盖仓库一方源码、生成适配器和构建配置。依赖源码、Flutter SDK、构建产物、Trellis/技能运行时不计入一方代码数量；JSON/图片/音频等内容资源通过相应加载与内容校验链路检查，不算源码。根目录分析配置排除了 `tools/**`，因此导入器另行运行了分析，未把根目录的零告警当作工具已检查的证据。

| 人工重点链路 | 核查内容 |
|---|---|
| 启动、Hive、凭据、家长保护 | 初始化失败与重试、加密密钥丢失、权限代次、安全存储错误、恢复屏障 |
| 备份、WebDAV、图片目录、缓存 | 解密/校验先于写入、补偿、原始键恢复、目录边界、流大小与超时、临时文件占用 |
| 仓储、统计、学习结算 | profile 隔离、幂等活动 ID、保存失败重试、恢复后旧写入、日历日期与复习边界 |
| 数学与应用题 | 生成约束、表达式显示语义、精确数值判分、结构化题目及独立抽样 |
| 诗词、教材、看图说话 | 结算与草稿、课程/资源解析、版本及归属、生成与点评、页面异步回调 |
| LLM、ASR、TTS、助手 | 请求取消、排队额度、协议解析、迟到连接、流式完成、会话切换与销毁 |
| 路由、原生与工具 | 参数缺失、APK 校验与安装桥、原生音频写入、发布脚本、PDF 导入原子写入 |

## 已修复的问题

P1 表示权限或数据覆盖风险；P2 表示功能错误、崩溃、资源泄漏或限额误扣。这里不为未证实的远程攻击情形赋予 CVSS 分数。

| 编号 | 等级 | 触发与影响 | 修复 | 关键回归证据 |
|---|---|---|---|---|
| A01 | P1 | 备份恢复排队期间家长锁定后重新解锁，旧请求只验证当前解锁状态，可能继续覆盖数据 | 在协调器、JSON/文件恢复入口捕获原授权代次；跨越异步等待后复验，事务仍保持完整提交/补偿 | `backup_protection_test.dart`：协调屏障、凭据队列、缓存队列三种等待，旧请求均被拒绝 |
| A02 | P2 | 腾讯实时 ASR 连接超时后底层连接仍成功，迟到 WebSocket 无人关闭 | 记录连接已放弃，迟到 socket 主动关闭，关闭异常不覆盖原错误 | `tencent_realtime_boundary_test.dart`：超时后完成连接，断言 socket 已关闭 |
| A03 | P2 | ASR 将字符串等畸形字段直接强制转换，流回调抛出未处理类型异常 | 校验响应码、握手标识、结果与结束字段；转换成可处理的 response 错误 | 坏握手、坏 index 两个故障注入测试；不返回伪成功文本 |
| A04 | P2 | ASR 未收到 `final=1` 就断流，部分转写被当作成功完成 | 完成由协议 final 标记决定；提前断流返回 network 错误 | 有部分文本、无 final、连接关闭时必须失败 |
| A05 | P2 | LLM 普通/流式请求及 Worker TTS 在额度队列中被取消，HTTP 没发送但本机可用次数仍减少 | 将取消/代次检查传入 `CloudUsageService.reserve(check:)`，在队列计数写入前检查 | `cloud_request_cancellation_test.dart`：三个入口均断言 HTTP 0 次、用量 0，后续预留恢复正常 |
| A06 | P2 | APK 非 2xx、目录失败、迟到响应或文件无法写入时下载流残留；逐块 add 缺少写入背压 | 所有退出路径触发取消并清理未消费响应；用 `addStream` 写入，保留文件错误并处理 `sink.done` | `update_client_test.dart`：四个新增场景，加既有大小限制/中途取消等，20 项通过 |
| A07 | P2 | 按固定 24 小时推进日期，夏令时地区统计跳日/重复、连续打卡错计、复习落错日期 | 用日历年月日和共用日期工具计算；同步统计、用量历史、复习、错题巩固及日期标签 | `TZ=America/New_York` 下修复前 3 天打卡可被算成 2/4 天；修复后日期测试通过 |
| A08 | P2 | 今日复习用 `<= 明天零点`，把次日零点条目提前加入今日 | 改为严格小于当地明天零点 | 当天 23:59 入列、次日 00:00 不入列 |
| A09 | P2 | 助手离页收尾微任务尚未执行时新会话开始请求，旧状态覆盖新会话 | 收尾同时检查原 `_sessionToken`，不能仅判断 busy | `assistant_chat_controller_test.dart`：旧请求收尾后新问题/会话保留；provider 销毁场景作为负控制 |
| A10 | P2 | 写字路由缺少 `target` query 时强制解包导致页面构建异常 | 缺失/空白参数显示既有缺少数据页面，并提供返回教材入口 | `app_router_test.dart`：无 target 路径正确兜底 |

对应实现可从以下文件开始审阅：

- [恢复协调器](lib/core/services/restore_coordinator.dart)、[备份服务](lib/core/services/backup_service.dart)
- [腾讯实时 ASR](lib/core/services/speech/tencent_realtime_asr_client.dart)
- [LLM 客户端](lib/core/services/llm/llm_client.dart)、[Worker TTS](lib/core/services/tts/worker_tts_client.dart)、[APK 下载](lib/core/services/update/update_client.dart)
- [日历工具](lib/core/utils/calendar_dates.dart)、[复习仓储](lib/data/repositories/review_repository.dart)、[打卡仓储](lib/data/repositories/check_in_repository.dart)
- [助手状态](lib/features/assistant/assistant_chat_controller.dart)、[路由](lib/core/routing/app_router.dart)

另发现基线 `check_project_contracts.py` 失败：被 Git 忽略的本地 `docs/PRIVACY.md` 落后于应用内 `assets/legal/PRIVACY.md`，缺少已存在的看图说话点评说明。按文档同步规范同步副本后检查通过。这是本地文档一致性修复，不计为代码漏洞。

## 复现与验证

先建立基线，再对确定问题写回归测试。A01、A02–A04、A05、A06、A07–A08、A09、A10 均有修复前失败记录。新增 24 个测试中也包含补充边界及原本通过的负控制，并非声称每个新增测试原本都会失败。

第一次最终全量运行暴露 A06 的额外文件不可写场景：`IOSink.addStream` 在文件打开失败时可能根本没有订阅响应。已据此补齐清理，保留该测试，再运行更新模块和全量测试。没有删除失败用例或弱化断言。

| 检查 | 结果 |
|---|---|
| 基线 `flutter analyze --no-pub` | 通过，0 问题 |
| 基线 `flutter test --no-pub --reporter expanded` | 3463 通过，12 跳过 |
| 最终 `flutter analyze --no-pub` | 通过，0 问题（4.1 秒） |
| 最终全量 Flutter 测试 | **3487 通过，12 跳过，0 失败**（6 分 3 秒） |
| 夏令时时区日历回归 | 7 通过；已加入 `.github/workflows/ci-test.yml` |
| Android 核心操作流程 | 5 通过，API 37 / Android 17 arm64 模拟器；debug 构建成功 |
| 数学独立抽样 | 12 学期 × 3000 = 36000 题，一致性/约束/括号整除错误为 0 |
| 诗词资源 `poem_importer validate` | 0 errors，0 warnings |
| 诗词工具与教材 Dart CLI 静态分析 | 均通过，0 问题 |
| Python 源码 AST | 21 个文件全部通过 |
| Python 安全/发布/项目契约测试 | 13 通过；另以文件名执行发布说明测试 4 通过 |
| Python PDF 导入器 | 使用锁定 requirements 的隔离 uv 环境，12 通过 |
| Android 兼容检查 | API 24 的五处声明一致 |
| PDFium 安全门禁 / 项目契约门禁 | 均通过 |
| 公开依赖漏洞查询 | OSV：206 个 Pub 包版本及 8 个 PyPI 包版本，返回已知漏洞 0 |
| `git diff --check` | 通过 |

主要复跑命令：

```bash
~/.pub-cache/bin/fvm flutter analyze --no-pub
~/.pub-cache/bin/fvm flutter test --no-pub --reporter expanded
TZ=America/New_York ~/.pub-cache/bin/fvm flutter test --no-pub test/data/repositories/calendar_boundaries_test.dart
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

Android 操作流程使用 `com.poemath.app.integration` 和隔离 Hive 目录，覆盖冷启动/诗词收藏、口算错题、公式收藏、每日打卡、离线备份恢复。没有操作真实用户数据库。

协议校验参考[腾讯实时语音识别官方协议](https://cloud.tencent.com/document/product/1093/48982)。依赖查询使用 [OSV 官方 API](https://google.github.io/osv.dev/post-v1-querybatch/) 及其 [Pub/PyPI 数据范围](https://google.github.io/osv.dev/data/)，只发送公开包名和版本。零命中只代表查询时该数据库没有匹配公告，不代表依赖已证明无漏洞，也不等同完整的原生传递依赖扫描。

## 未算作缺陷的核查结果

- 当前锁定 Dart SDK 的 HTTP 重定向实现会按同源规则移除敏感头；没有把旧文档措辞推断为当前版本存在凭据泄漏。
- 既有产品契约允许儿童完成已发布教材练习，不要求每一道题重复输入家长 PIN；未将该行为改为额外授权流程。
- 错题连续练习推进巩固轮次符合现有仓储规范；未凭偏好改变间隔规则。
- 助手 provider 销毁后迟到响应的负控制原本就通过；本轮修复的是旧收尾微任务覆盖新会话，不混淆二者。

## 验证边界与交付状态

全量测试中跳过的 12 项来自 `textbook_course_real_pdf_test.dart`：需要本地 12 册 PDF 以及显式 `TEXTBOOK_PDF_DIRECTORY`、`TEXTBOOK_PDFIUM_LIBRARY`。本轮未配置这些专用输入；跳过数量与基线一致。

本轮未验证 iOS 构建/真机、Android 最低 API 24 真机、不同厂商系统 TTS、真实麦克风、真实付费腾讯/LLM 服务、真实 WebDAV 服务器和真实升级安装。已执行的 5 条 Android 流程也不等同全部 11 个 integration 文件均已设备运行。内容重建脚本只做源码与语法检查，未批量重写现有资源。

完整测试日志在本机 `/tmp/poemath-audit-*.log`；它们是临时文件，关键结果已摘录到本文。任务与详细检索位置保存在 `.trellis/tasks/11-08-full-project-audit/`，跨层契约已更新到 `.trellis/spec/backend/audit-correctness-contracts.md`；这些目录按项目策略被 Git 忽略。审查结束时，代码及本报告保留在工作区供审阅，未提交、推送或发布。后续提交记录见下文。

## 按功能提交（2026-11-08）

用户随后确认按功能分批提交，修复代码与对应回归测试分为以下七个提交；本报告和文件清单另作一个文档提交。

| 提交 | 功能与修复编号 |
|---|---|
| `bf66353` | 备份恢复授权失效保护（A01） |
| `c047a9f` | 实时语音识别连接清理、协议校验与完成判定（A02–A04） |
| `a332c70` | 云请求取消后保留本机额度（A05） |
| `766c650` | APK 下载失败清理与文件写入流量控制（A06） |
| `67278e0` | 日历统计、复习边界及夏令时 CI（A07–A08） |
| `f52dc94` | 助手旧请求收尾与新会话隔离（A09） |
| `0287c93` | 写字路由缺少目标参数时兜底（A10） |

提交前复核清单中的 905 个文件，哈希全部与上述已验证版本一致。CSV 清单统一为 LF 换行，905 条记录内容保持不变，包含新增文档的提交差异通过 `git diff --check`。代码与审查文档均已在本地按功能提交，未推送或发布。
