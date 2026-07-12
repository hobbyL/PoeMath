# PoeMath 诗算宝

> 面向 6-12 岁儿童的诗词背诵与口算训练助手

[![Flutter](https://img.shields.io/badge/Flutter-3.44-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 简介

**诗算宝 (PoeMath)** 是一款完全离线的 Flutter 应用，专为小学 1-6 年级学生设计，将**古诗词背诵**与**口算训练**融合在一个轻量、无广告、零隐私风险的学习工具中。

### 核心特色

- 🏮 **1000+ 首古诗词**：覆盖人教版部编教材 130 首 + 经典扩展 + 探索层，按年级/朝代/作者/主题分类
- 🧮 **12 类口算题型**：紧贴人教版数学课标，1-6 年级 12 个学期精准配置
- 📐 **60+ 数学公式库**：分类浏览、参数说明、记忆技巧、例题
- 🎯 **智能错题分析**：6 类错因规则（进位遗漏/退位遗漏/口诀错误/运算顺序/余数/小数点）
- 📖 **艾宾浩斯复习**：间隔 [1, 3, 7, 14, 30] 天的科学复习调度
- ⭐ **游戏化激励**：每日打卡 → 星星累积 → 等级晋升（童生→状元→诗仙）→ 成就勋章
- 🔒 **完全离线**：不收集任何个人信息，无广告，无内购，无第三方 SDK

## 功能截图

> *截图待补充*

## 技术架构

| 层级 | 技术选型 |
|------|---------|
| UI | Flutter 3.44 + Material Design 3 |
| 状态管理 | Riverpod (Provider/StateProvider/Family) |
| 路由 | GoRouter (Navigator 2.0) |
| 本地存储 | Hive (NoSQL, 手写 TypeAdapter) |
| 口算引擎 | 纯 Dart (lib/math_engine/) |
| 主题系统 | 双主题（国风诗词 / 童趣口算）|

### 目录结构

```
lib/
├── core/              # 常量、路由、主题、工具
├── data/              # Hive 模型、仓储、Provider
├── features/          # 功能模块
│   ├── home/          # 首页仪表盘
│   ├── poem/          # 诗词模块
│   ├── math/          # 口算模块
│   ├── formula/       # 公式知识库
│   ├── profile/       # 个人中心
│   └── shell/         # Shell + 导航 + 启动页
├── math_engine/       # 口算引擎 (纯 Dart)
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

## 数据来源

- 古诗词数据基于公开古诗词数据库整理，经人工校对
- 数学课标对齐人教版（PEP）小学数学教材
- 所有数据内置于应用，无需网络

## 隐私政策

诗算宝严格保护用户隐私，详见 [隐私政策](docs/PRIVACY.md)。

- ✅ 完全离线运行，不发送任何网络请求
- ✅ 不收集、存储或传输任何个人信息
- ✅ 不包含任何广告 SDK 或追踪代码
- ✅ 不包含任何内购或付费功能
- ✅ 所有数据仅存储在用户设备本地

## 许可证

MIT License

## 版本历史

详见 [CHANGELOG](docs/CHANGELOG.md)。
