# PoeMath 韵算

> 面向 6-12 岁儿童的诗词背诵与口算训练助手

[![Flutter](https://img.shields.io/badge/Flutter-3.44-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 简介

**韵算 (PoeMath)** 是一款**离线优先**的 Flutter 应用，专为小学 1-6 年级学生设计，将**古诗词背诵**与**口算训练**融合在一个轻量、无广告、无内购的学习工具中。

核心学习（诗词 / 口算 / 公式 / 打卡）全程本地完成，飞行模式可用；备份同步与应用更新为**可选**能力，需用户主动开启。

### 核心特色

- 🏮 **1000+ 首古诗词**：核心层约 130 首（部编教材向）+ 扩展层 + 探索层；支持年级/朝代/作者/主题浏览
- 🧮 **12 类口算题型**：紧贴人教版数学课标，1-6 年级 12 个学期配置
- 📐 **数学公式库**：分类浏览、参数说明、记忆技巧、例题（持续扩充）
- 🎯 **智能错题分析**：6 类错因规则（进位遗漏/退位遗漏/口诀错误/运算顺序/余数/小数点）
- 📝 **诗词测试**：填空测试（补全诗句）+ 选择题（上句选下句），自动生成题目、即时反馈
- 📖 **渐进式背诵**：首字提示 → 半隐模式 → 全隐模式 → 默写，四级递进
- 🧠 **艾宾浩斯复习**：间隔 [1, 3, 7, 14, 30] 天的科学复习调度，首页提醒 + 复习列表
- ⭐ **游戏化激励**：每日打卡 → 星星累积 → 等级晋升（童生→状元→诗仙）→ 成就勋章
- 🎉 **感官反馈**：自研 confetti 粒子特效、flutter_animate 庆祝弹窗、音效、触觉反馈
- 💾 **数据备份/恢复**（可选）：一键导出学习数据为 JSON，跨设备恢复
- ☁️ **WebDAV 云端同步**（可选）：同步到**用户自有** WebDAV，凭据加密存储
- 🔄 **应用内更新**（可选）：检查新版本、下载 APK、校验安装（需配置更新源）
- 🔒 **隐私友好**：不收集个人信息到开发者服务器；无广告、无内购、无分析追踪 SDK

## 功能截图

> *截图待补充*

## 技术架构

| 层级 | 技术选型 |
|------|---------|
| UI | Flutter 3.44 + Material Design 3 |
| 状态管理 | Riverpod (Provider/StateProvider/Family) |
| 路由 | GoRouter (Navigator 2.0) |
| 本地存储 | Hive (NoSQL) + flutter_secure_storage (加密凭据) |
| 口算引擎 | 纯 Dart (lib/math_engine/) |
| 主题系统 | 双主题（国风水墨 / 童趣马卡龙）|
| 导航 | 4-Tab NavigationBar（首页/诗词/口算/我的）|

### 目录结构

```
lib/
├── core/              # 常量、路由、主题、工具、服务
│   ├── routing/       # GoRouter 路由定义
│   ├── theme/         # 双主题系统 (诗词/口算)
│   ├── widgets/       # 共享组件 (ColoredCard, AppTile, ConfettiOverlay, CelebrationDialog)
│   └── services/      # TTS、音效、触觉、备份、应用更新服务
├── data/              # Hive 模型、仓储、Provider
│   ├── models/        # 15 个 Hive 模型
│   └── repositories/  # 14 个仓储类
├── features/          # 功能模块
│   ├── home/          # 首页仪表盘 (打卡/统计/复习提醒)
│   ├── poem/          # 诗词模块 (列表/详情/背诵/测试/复习)
│   │   └── quiz/      # 测试引擎 + 题目模型
│   ├── math/          # 口算模块 (练习/错题本)
│   ├── formula/       # 公式知识库
│   ├── profile/       # 个人中心 (设置/更新/数据备份恢复)
│   └── shell/         # Shell + 4-Tab 导航 + 启动页
├── math_engine/       # 口算引擎 (纯 Dart, 12 类生成器)
└── app.dart           # 应用根 Widget
```

## 开发环境

### 前置条件

- [Flutter](https://flutter.dev) >= 3.44 (推荐使用 [FVM](https://fvm.app) 管理)
- Dart >= 3.12
- Android SDK (API Level 21+)

### 快速开始

```bash
# 克隆项目
git clone <repo-url>
cd PoeMath

# 安装依赖
flutter pub get

# 运行
flutter run

# 运行测试
flutter test

# 静态分析
flutter analyze

# 构建 Release APK
flutter build apk --release
```

## CI/CD

项目配置了两条 GitHub Actions 流水线：

### 自动测试（push / PR）

每次 push 到 `main` 或提交 PR 时自动触发：

```
analyze → test
```

在 GitHub 仓库的 **Actions** 页面查看运行状态。

### 自动构建发版（tag）

打 `v*` 格式的 tag 时自动触发完整构建并发布到 GitHub Release：

```
analyze → test → build release APK → 创建 GitHub Release
```

#### 使用方式

```bash
# 1. 推送代码，等 CI 测试通过
git push origin main

# 2. 打 tag 触发构建
git tag v1.0.0
git push origin v1.0.0
```

构建完成后在 [Releases](../../releases) 页面下载 APK。

#### 版本号规则

- tag `v1.2.3` → 应用版本名 `1.2.3`，构建号 `10203`
- 应用内「我的」页面底部自动显示当前版本号

#### 签名配置

使用固定签名密钥，确保每次构建的 APK 可覆盖安装。需在 GitHub 仓库 **Settings → Secrets → Actions** 中配置：

| Secret | 说明 |
|--------|------|
| `KEYSTORE_BASE64` | base64 编码的签名文件 |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | key 别名 |
| `KEY_PASSWORD` | key 密码（**必须与 `KEYSTORE_PASSWORD` 相同**） |

> ⚠️ **重要**：Java 9+ 的 keytool 默认生成 PKCS12 格式的 keystore，PKCS12 **不支持 storePassword 和 keyPassword 不同**。即使创建时指定了不同的 `-keypass`，也会被静默忽略。因此 `KEY_PASSWORD` 和 `KEYSTORE_PASSWORD` 必须设置为相同的值。

生成签名密钥：

```bash
keytool -genkey -v \
  -keystore poemath-release.jks \
  -alias poemath \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -storepass YOUR_PASSWORD \
  -keypass YOUR_PASSWORD \
  -dname "CN=PoeMath, O=PoeMath, L=Beijing, C=CN"

# 转 base64 后填入 KEYSTORE_BASE64（从文件复制，避免终端截断）
base64 -i poemath-release.jks -o keystore.b64
cat keystore.b64 | pbcopy
```

### 应用内更新（阿里云 OSS）

应用支持检查新版本、下载 APK 并安装。更新文件托管在阿里云 OSS，CI 构建时自动上传。

#### 工作流程

```
打 tag → CI 构建 APK → 上传到 OSS → 生成 latest.json
→ 用户在设置页点击"检查更新" → 对比版本 → 下载 → MD5 校验 → 安装
```

#### GitHub Secrets 配置

| Secret / Variable | 说明 | 示例值 |
|-------------------|------|--------|
| `ALIYUN_OSS_ACCESS_KEY_ID` | 阿里云 AccessKey ID | `LTAI5t...` |
| `ALIYUN_OSS_ACCESS_KEY_SECRET` | 阿里云 AccessKey Secret | `***` |
| `ALIYUN_OSS_ENDPOINT` | OSS Endpoint | `oss-cn-hangzhou.aliyuncs.com` |
| `ALIYUN_OSS_BUCKET` | Bucket 名称 | `cloudm` |
| `ALIYUN_OSS_APP_UPDATE_OSS_PREFIX` | OSS 目录前缀 | `poemath/android/stable` |
| `ALIYUN_OSS_APP_UPDATE_DOWNLOAD_BASE_URL` | 下载 Base URL | `https://cloudm.oss-cn-hangzhou.aliyuncs.com` |

> `UPDATE_CHECK_URL` 由 CI 自动拼接并通过 `--dart-define` 注入，无需单独配置。未配置时，设置页的"检查更新"入口自动降级为不可用状态。

## 功能模块

### 诗词模块

| 功能 | 说明 | 页面 |
|------|------|------|
| 诗词列表 | 按年级筛选、搜索 | `poem_tab_page` |
| 诗词详情 | 全文、拼音、译文、注释、赏析、名句 | `poem_detail_page` |
| 渐进式背诵 | 首字提示 → 半隐 → 全隐 → 默写 | `poem_recite_page` |
| 填空测试 | 自动挖空诗句后半，输入答案 | `poem_quiz_page` |
| 选择题 | 上句出题，4 选 1 选下句 | `poem_quiz_page` |
| 复习计划 | 艾宾浩斯 5 轮复习，首页提醒 | `poem_review_page` |
| TTS 朗读 | 全文语音朗读，逐句高亮，可调语速 | `poem_detail_page` |

### 口算模块

| 功能 | 说明 |
|------|------|
| 12 类题型 | 加减法 / 乘法口诀 / 有余除法 / 多位数乘除 / 混合运算 / 运算律 / 小数 / 分数 / 百分数 / 简易方程 / 比例 / 正负数 |
| 比大小模式 | 比较两个表达式大小，>, <, = 三按钮交互 |
| 竖式计算 | 加减乘法竖式渲染，数字右对齐，输入答案 |
| 年级适配 | 1-6 年级 12 个学期独立配置，难度递进 |
| 错题诊断 | 6 类错因规则 + 分步解题过程 |
| 错题本 | 记录错题、重做、标记已掌握 |
| 限时挑战 | 固定时间模式 / 续命模式，挑战记录持久化 |

## 数据来源

- 古诗词数据基于公开古诗词数据库整理，经人工校对
- 数学课标对齐人教版（PEP）小学数学教材
- 所有数据内置于应用，无需网络

## 隐私政策

韵算严格保护用户隐私。**完整政策**（与应用内同源）：

- 仓库文档：[docs/PRIVACY.md](docs/PRIVACY.md)
- 应用资源：`assets/legal/privacy_policy.md`（「我的 → 关于 → 隐私政策」读取此文件）

要点：

- ✅ **离线优先**：核心学习不依赖网络，飞行模式可用
- ✅ 不收集个人信息到开发者服务器；无广告 / 分析 / 追踪 SDK
- ✅ 无内购或付费功能
- ✅ 学习数据默认仅存本地；备份 / WebDAV / 检查更新 / 跟读 / 通知需用户主动操作或授权
- ✅ 权限与行为对照见隐私政策第 4–5 节（含 `INTERNET`、麦克风、通知、安装 APK 等说明）
- ✅ 联系方式：应用内关于页；开源发行可通过仓库 Issue（客服邮箱待渠道确定后补充）

## 许可证

MIT License

## 版本历史

详见 [CHANGELOG](docs/CHANGELOG.md)。
