# Phase 0: 项目脚手架 + 主题系统

> 父任务：`../07-12-poemath-mvp/`（PRD/design/implement 见父任务）
> 依赖：无（第一个子任务）

## Goal

搭建 PoeMath Flutter 项目骨架，建立**双主题系统**（诗词国风水墨 + 口算童趣马卡龙），并接入 Riverpod 状态管理、5-Tab 底部导航和路由系统，为后续所有子任务提供开发基础。

## Requirements

### R0.1 项目初始化
- **R0.1.1** 使用 `flutter create` 创建项目（package 名 `com.poemath.app`）
- **R0.1.2** 目标 Android SDK 34，最低 Android SDK 21
- **R0.1.3** 项目名 `poemath`，语言 Dart 3.x

### R0.2 依赖管理
- **R0.2.1** 加入核心依赖（`pubspec.yaml`）：
  - `flutter_riverpod`
  - `hive`, `hive_flutter`
  - `lpinyin`
  - `flutter_tts`
  - `flutter_math_fork`
  - `lottie`
  - `intl`
  - `path_provider`
  - `shared_preferences`
- **R0.2.2** 开发依赖：`hive_generator`, `build_runner`, `flutter_lints`
- **R0.2.3** 版本使用最新稳定版，锁定版本

### R0.3 项目目录结构
- **R0.3.1** 建立分层目录（对齐父任务 design.md §2.1）：
  ```
  lib/
  ├── main.dart
  ├── app.dart
  ├── core/
  │   ├── theme/           # 主题系统
  │   ├── routing/         # 路由
  │   ├── constants/       # 常量
  │   └── utils/
  ├── data/                # 数据层（Phase 2 填充）
  ├── domain/              # 领域层（Phase 2/3 填充）
  ├── features/            # 功能模块（后续 Phase 填充）
  │   ├── home/
  │   ├── poem/
  │   ├── math/
  │   ├── formula/
  │   └── profile/
  └── shared/              # 通用 widgets
  ```

### R0.4 双主题系统
- **R0.4.1** 定义 `AppTheme` 类，含两套 `ThemeData`：
  - **诗词国风主题**：宣纸色 `#F9F7F2` + 墨绿 `#436444` + 朱砂 `#B35C5C` + serif 字体
  - **口算童趣主题**：马卡龙紫/黄/粉/蓝 + 白底 + 圆润字体（Nunito/Zen Maru Gothic）
- **R0.4.2** 主题令牌抽象（对齐父任务 design.md §5）：
  - colors: primary/secondary/background/surface/error/textPrimary/textSecondary
  - typography: displayLarge/headlineMedium/titleLarge/bodyLarge/bodyMedium/labelMedium/poetryText
  - spacing: xs=4/sm=8/md=16/lg=24/xl=32
  - radius: small=8/medium=16/large=24
- **R0.4.3** 主题切换机制：通过 Riverpod `themeModeProvider` + `activeSubjectProvider`（poem/math）动态切换
- **R0.4.4** 支持深色模式（护眼要求 R5.7），暂用默认深色映射

### R0.5 底部导航
- **R0.5.1** 5-Tab 底部导航：首页 / 诗词 / 学习(中央凸起) / 口算 / 我的
- **R0.5.2** 中央凸起按钮：白色圆形 + 阴影 + Y 轴上移，用 `Shape + ClipPath` 实现凹槽
- **R0.5.3** 图标可点击区域 ≥ 44pt

### R0.6 路由系统
- **R0.6.1** 使用 `Navigator 2.0` + Riverpod 管理路由栈
- **R0.6.2** 定义主要路由常量（`app_routes.dart`）：
  - `/` (Home)
  - `/poem/list` (诗词列表)
  - `/poem/detail/:id` (诗词详情)
  - `/poem/recite/:id` (背诵)
  - `/math/practice` (口算练习)
  - `/math/mistake` (错题本)
  - `/formula/list` (公式)
  - `/profile` (我的)

### R0.7 静态资源
- **R0.7.1** 建立 `assets/` 目录（`fonts/`, `icons/`, `lottie/`, `data/`, `sounds/`）
- **R0.7.2** 在 `pubspec.yaml` 声明资源
- **R0.7.3** 添加占位字体（NotoSerifSC / NotoSansSC / Nunito）

### R0.8 应用入口
- **R0.8.1** `main.dart` 调用 `Hive.initFlutter()`、`ProviderScope` 包裹 `App`
- **R0.8.2** `App` widget 加载主题、路由、Locale（zh_CN）
- **R0.8.3** 启动页 SplashScreen（占位 Lottie + 品牌名"诗算宝"）

### R0.9 代码规范
- **R0.9.1** 配置 `analysis_options.yaml`：启用 `flutter_lints`
- **R0.9.2** 目录内含 `README.md` 说明分层职责

## Acceptance Criteria

- [x] **AC0.1** `flutter run` 可在 Android 上启动、看到启动页 + 5-Tab 底部导航
- [x] **AC0.2** 5-Tab 切换正常，中央凸起按钮视觉正确
- [x] **AC0.3** 双主题切换：手动触发 poem/math 主题时颜色/字体正确切换
- [x] **AC0.4** 深色模式切换正常
- [x] **AC0.5** `flutter analyze` 无错误
- [x] **AC0.6** `flutter test` 通过（226 tests passing）
- [x] **AC0.7** 目录结构符合父任务 design.md §2.1

## Out of Scope

- 具体的诗词/口算/公式功能（后续 Phase）
- 真实数据加载（Phase 2）
- 完整的 UI 页面（Phase 4/5/6）

## Dependencies

- **上游**：无
- **下游**：Phase 1-7 全部依赖本 Phase
