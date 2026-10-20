# PoeMath 审查修复记录

日期：2026-10-20。审查基线：`main` / `698f7e5`。

本记录对应此前拆分的 19 项问题。代码修复已完成；最低 Android 版本的 CI 执行和真实设备验收仍按下文单独记录。故障测试使用临时目录、合成凭据和隔离数据，没有调用生产服务。修复经验证后已按用户要求分批提交到本地 `main`，未推送或发布。

## 功能提交

| 提交 | 功能范围 |
|---|---|
| `69af7d0` | 数据库密钥异常处理、加密迁移与原文件保留 |
| `725e12b` | 学习结算幂等、日报统计、完成日期与备份字段 |
| `92f291e` | 网络超时及取消、资源预算、诊断日志脱敏 |
| `568cac3` | 整包备份与本地快照加密、设备云用量、隐私说明 |
| `cc09b9d` | SDK 固定、Android 集成门禁、发布版本与签名配置 |
| `45f5c9e` | 公共数学卡片组件统一 |

`backup_service.dart` 的学习字段和备份加密改动、README 的备份说明和版本规则分别按功能暂存。提交拆分没有改变已验证代码的内容。

## 逐项修复

| 编号 | 原问题 | 已落实的修改 | 主要代码 / 验证位置 |
|---|---|---|---|
| 1 | 安全存储暂时读失败会覆盖旧密钥并删除数据库 | 读取异常作为可重试错误传播，不创建替代密钥；无法解密的文件先隔离留底，启动提供准确提示 | `hive_encryption_key_provider.dart`、`hive_encryption_key_resolver.dart`；对应密钥服务测试 |
| 2 | 加密迁移先清空原文件，持久备份太晚 | 从内存副本读取和解绑对象；先持久备份，再写临时密文，逐字段校验后切换；失败保留原数据及恢复依据 | `hive_encryption_migration.dart`、`hive_value_snapshot.dart`；`encrypted_box_roundtrip_test.dart` |
| 3 | 部分迁移重启后跳过其余明文，正常启动可能截断它们 | 每次逐个检查全部 19 个 box；继续剩余迁移；生产打开禁用截断式 `crashRecovery` | `hive_encryption_key_resolver.dart`、`hive_boxes.dart`；混合明密文及隔离测试 |
| 4 | 结算业务与幂等标记分开写，重试重复累计；失败污染内存对象 | 活动 ID 与业务字段同一次 `put` 持久化；更新采用新对象，同通道串行化，保留旧 meta 标记兼容 | 4 个结算模型及仓储、`activity_settlement_ledger.dart`；`audit_fix_20261020_test.dart` |
| 5 | 恢复旧备份会清零本机今日云用量 | 设备消费计数不再导出、恢复或参与学习数据回滚；旧备份的计数只验证，不应用；额度设置仍可迁移 | `backup_service.dart`、`cloud_usage_service.dart`；云用量和备份测试 |
| 6 | 日报存在完成活动后，遗漏同日未完成练习 | 增加明确的会话完成状态；完成数据聚合后补入未完成会话的已答数与时长；3 题未完成加 10 题完成显示 13 题 | `math_session.dart`、`stats_chart_providers.dart`；审计回归测试 |
| 7 | 跨日结算重试把每日汇总记到重试日 | 新增 `updateForDate(completedAt)`；数学和诗词各结算入口共用冻结完成日期 | `check_in_repository.dart`、各练习页面；固定日期及备份往返测试 |
| 8 | Authorization 脱敏保留真实令牌 | 隐藏完整 Bearer / Basic 值、多词及带引号的敏感字段；日志标签同样脱敏；断言原秘密不存在 | `diagnostic_buffer.dart`、`diagnostic_buffer_test.dart` |
| 9 | WebDAV 只对响应头超时，正文可能一直等待；取消未终止请求 | 统一请求总期限，覆盖头和正文；中止底层请求及订阅；共享连接池保持可用，取消后的晚到响应也清理 | `bounded_http_client.dart`、WebDAV / LLM / TTS / 更新 / ASR 客户端；网络边界测试 |
| 10 | 外部响应、备份、AI 上下文及音频缓存缺少资源预算 | 按实际流入字节计数；备份 32 MiB、LLM 和更新元数据 2 MiB、TTS 响应及缓存 8 MiB；上下文限制 100 条 / 256 KiB并保留完整工具调用轮次；SSE 单行和总期限受限 | 各网络客户端、`backup_payload_cipher.dart`、`tts_service.dart`；超限、停滞、虚假长度及缓存淘汰测试 |
| 11 | 加密数据库另存明文本地快照；外部口令仅保护凭据 | 新建本地历史使用独立设备密钥认证加密，旧明文安全迁移；外部备份设置口令后整包认证加密；整包解密后可选择跳过凭据 | `backup_history_service.dart`、`backup_payload_cipher.dart`、`backup_import_flow.dart`；加密及页面测试 |
| 12 | 自动更新触发与隐私说明不一致 | 明确配置更新地址的 Android 应用在启动、恢复前台时自动检查，最短间隔 1 小时；安装仍需用户确认 | `assets/legal/privacy_policy.md`、`about_page.dart`、`README.md` |
| 13 | 云用量迁移行为与政策不一致 | 统一为设备消费计数不迁移，额度设置随学习设置迁移 | `backup_service.dart`、隐私政策及备份说明 |
| 14 | 仓库隐私副本落后，备份加密文案沿用旧实现 | 更新应用政策并同步本地 `docs/PRIVACY.md`；契约检查校验存在的本地副本；整包口令和设备快照文案与实现一致 | `assets/legal/privacy_policy.md`、`tools/check_project_contracts.py`；本地文档镜像检查 |
| 15 | 测试等待不稳定，迁移及脱敏断言不足，CI 缺少门禁 | 修正异步等待与测试隔离；使用真实 Hive 对象、真实文件写入故障及关闭重开验证；加入内容、发布脚本及 Android 集成门禁 | `test/`、`integration_test/`、三份 CI 工作流 |
| 16 | FVM 使用浮动 stable，可能与 CI 不一致 | 本地和 CI 均固定 Flutter 3.44.6；契约检查阻止版本漂移 | `.fvmrc`、CI 工作流、`check_project_contracts.py` |
| 17 | versionCode 映射可能碰撞或倒退 | 严格验证 tag、minor / patch 范围、Android 数值范围及历史单调性；旧越界版本占用的 code 也参与冲突检查；历史生成复用同一解析器 | `tools/release_version.py`、`release_contracts_test.py`、发布工作流 |
| 18 | 签名秘密直接插入 shell 和 properties，特殊字符会破坏解析 | 秘密通过环境变量传入；properties 正确转义空格、反斜杠、换行和 Unicode；keytool 从环境变量读取密码 | `tools/write_signing_properties.py`、发布工作流；合成特殊字符测试 |
| 19 | 两个数学卡片违反统一组件规范 | 改用 `ColoredCard` 和间距令牌；公共组件支持原卡片边框需求 | `practice_entry_card.dart`、`grade_semester_card.dart`、`colored_card.dart` |

## 验证结果

使用本地 `.fvm/flutter_sdk/bin/flutter`，SDK 为 Flutter 3.44.6 / Dart 3.12.2。

| 检查 | 结果 |
|---|---|
| `flutter test --reporter expanded` | 2043 项全部通过，退出码 0 |
| `flutter analyze` | 通过，No issues found |
| `python3 tools/check_android_compatibility.py` | API 24，5 个声明一致 |
| `python3 tools/check_project_contracts.py` | 通过，包含 SDK 和存在的隐私政策镜像检查 |
| `python3 -m unittest discover -s tools -p '*_test.py'` | 2 个发布契约用例通过 |
| `python3 tools/release_notes_test.py` | 4 个用例通过 |
| `poem_importer validate` | errors 0 / warnings 0 |
| 本地 Android 集成测试 | API 37 arm64 模拟器，5 条旅程全部通过 |
| `git diff --check` | 通过 |

全量测试后只补齐了 4 处测试代码尾逗号及说明文档；相关 11 项测试再次通过，静态分析再次通过。

本次本地测试日志保存在 `/tmp/poemath-fix-full-tests.log`、`/tmp/poemath-fix-analyze.log`、`/tmp/poemath-fix-integration.log` 和 `/tmp/poemath-fix-content.log`。`/tmp` 日志不是持久发布产物。

## 验证与兼容边界

- 新增 CI 使用 API 24 / x86_64 模拟器，普通 CI 和发布流程均调用，发布构建依赖集成测试成功。本轮未推送，因此没有 GitHub Actions 执行结果；本地 API 37 通过不能代替 API 24 验证。
- Android 集成流程使用 debug APK，尚未完成混淆 release APK 的设备验收。安全存储故障使用合成存储及临时文件测试，不能代替各真机的密钥库验证。
- 新版本继续接受旧明文备份和旧模型缺省字段。整包加密采用版本 2 信封，旧客户端需要升级后才能读取；Base64 有体积开销，可加密的明文上限实际低于 32 MiB。
- 本地历史依赖原设备密钥，换机时应使用口令保护的外部备份。文件名、快照时间、原因及信封元数据仍可见；学习正文和聊天正文已加密。旧明文迁移保留原始 JSON 字段，已有加密历史在读取时认证。
- 没有口令的外部导出仍为明文；界面已经明确提示。整包解密后取消“同时恢复安全凭据”会跳过凭据解密及写入，保留本机现有凭据。
- 本地 `docs/PRIVACY.md` 和 `.trellis/spec/` 按仓库现有规则忽略，没有强制加入版本控制。CI 以应用资产政策为源，镜像存在时才检查相等。

这份记录说明上述 19 项已采取的修复与验证范围，不代表项目不存在其他尚未发现的问题。
