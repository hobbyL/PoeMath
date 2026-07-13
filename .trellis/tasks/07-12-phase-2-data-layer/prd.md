# Phase 2: Hive 数据层 + Riverpod 状态骨架

> 父任务：`../07-12-poemath-mvp/`
> 依赖：Phase 0（脚手架）+ Phase 1（数据资产）

## Goal

搭建 App 的**统一数据层**：11 个 Hive Box、首次启动数据导入流水线、所有 Repository 与核心 Provider。Phase 4/5/6 的 UI 层都直接消费这里定义的 Provider，无需再触碰 Hive。

## Requirements

### R2.1 Hive 数据模型（`lib/data/models/`）
- **R2.1.1** 定义所有 `@HiveType` 领域模型：
  - Poem / Author / Formula（静态数据）
  - PoemProgress / PoemFavorite / ReviewSchedule（诗词动态数据）
  - MathMistake / MathSession（口算动态数据）
  - FormulaFavorite / Achievement / CheckIn / UserStats（通用）
- **R2.1.2** 每个模型对应一个 `TypeAdapter`，通过 `hive_generator` + `build_runner` 生成
- **R2.1.3** 所有含 profileId 的模型都有 `profileId` 字段（默认写入 `'default'`）

### R2.2 Box 定义与初始化（`lib/data/hive/hive_init.dart`）
- **R2.2.1** 11 个 Box：
  - `poemBox` / `authorBox` / `formulaBox`（静态数据）
  - `poemProgressBox` / `poemFavoriteBox` / `reviewScheduleBox`
  - `mathMistakeBox` / `mathSessionBox`
  - `formulaFavoriteBox` / `achievementBox` / `checkInBox` / `userStatsBox`
  - `settingsBox` / `metaBox`
- **R2.2.2** `HiveInit.init()`：
  1. 初始化 Hive 目录
  2. 注册所有 TypeAdapter
  3. 打开所有 Box（poemBox/authorBox/formulaBox 用 LazyBox）
  4. 检查 `metaBox['data_version']`，若与当前 assets 版本不符，触发首次导入

### R2.3 首次导入服务（`lib/data/bootstrap/asset_importer.dart`）
- **R2.3.1** 从 `assets/data/poems_core.json`、`poems_extended.json`、`poems_explore.json` 读取诗词
- **R2.3.2** 从 `assets/data/authors.json` 读取作者
- **R2.3.3** 从 `assets/data/formulas.json` 读取公式
- **R2.3.4** 批量 `putAll()` 写入对应 Box
- **R2.3.5** 更新 `metaBox['data_version']` 为当前 assets 版本
- **R2.3.6** 显示导入进度（0-100%）供 SplashScreen 消费

### R2.4 索引服务（`lib/data/indexes/`）
- **R2.4.1** 应用启动后构建内存索引（一次性成本）：
  - `gradeIndex: Map<int, List<String>>` — 年级 → 诗词 ID 列表
  - `authorIndex: Map<String, List<String>>` — 作者 → 诗词 ID 列表
  - `dynastyIndex: Map<String, List<String>>` — 朝代 → 诗词 ID 列表
  - `tagIndex: Map<String, List<String>>` — 主题标签 → 诗词 ID 列表
  - `layerIndex: Map<String, List<String>>` — 层级 → 诗词 ID 列表
- **R2.4.2** 索引由 Riverpod 缓存，App 生命周期内一次构建

### R2.5 Repository 层（`lib/data/repositories/`）
- **R2.5.1** `PoemRepository`：诗词 CRUD、按索引筛选
- **R2.5.2** `AuthorRepository`：作者查询
- **R2.5.3** `FormulaRepository`：公式 CRUD、分类查询
- **R2.5.4** `PoemProgressRepository`：进度读写、按 profileId 过滤
- **R2.5.5** `PoemFavoriteRepository` / `ReviewScheduleRepository`
- **R2.5.6** `MathMistakeRepository` / `MathSessionRepository`
- **R2.5.7** `FormulaFavoriteRepository` / `AchievementRepository` / `CheckInRepository` / `UserStatsRepository`
- **R2.5.8** 所有含 profile 数据的 Repository 通过 `ProfileScopedKey.buildKey()` 组装 key

### R2.6 Profile 管理（`lib/data/profile/`）
- **R2.6.1** `ProfileService`：读写 `settingsBox['activeProfileId']`
- **R2.6.2** MVP 阶段恒返回 `'default'`
- **R2.6.3** `ProfileScopedKey`：统一的 Box key 构造工具

### R2.7 Riverpod Provider 骨架（`lib/features/*/state/`）
- **R2.7.1** 各 Repository 对应的 Provider（用 riverpod_generator）
- **R2.7.2** 核心 Provider：
  - `poemProvider(String id)` — 单首诗词
  - `poemListByGradeProvider(int grade)` — 按年级列表
  - `poemProgressProvider(String poemId)` — 进度状态
  - `checkInProvider` — 打卡状态
  - `userStatsProvider` — 用户统计
  - `activeProfileIdProvider` — 当前档案 ID

### R2.8 单元测试
- **R2.8.1** Repository 层 100% 单元测试覆盖
- **R2.8.2** AssetImporter 集成测试（导入 fixture JSON → 验证 Box 内容）
- **R2.8.3** 索引构建正确性测试

## Acceptance Criteria

- [x] **AC2.1** 应用冷启动可完成首次导入（耗时 <5 秒） → bootstrap.dart 实现完成
- [x] **AC2.2** 首次导入后，二次启动跳过导入，直接读取 Box → data_version 检查实现
- [~] **AC2.3** 所有 Repository 通过单元测试 → **Repository 层未有专门单元测试，模型层有测试**
- [x] **AC2.4** 索引服务能正确按 grade/author/dynasty/tag/layer 筛选 → PoemRepository 内联索引
- [x] **AC2.5** ProfileScopedKey 生成的 key 全部包含当前 profileId 前缀 → ProfileScope 实现
- [x] **AC2.6** 修改 assets 版本号后，二次启动能触发重新导入 → bootstrap.dart data_version 检查
- [x] **AC2.7** 代码通过 `flutter analyze` 无警告 → 0 issues
- [~] **AC2.8** 单元测试覆盖率 ≥80% → **Repository 层测试缺失，整体覆盖率待确认**

## Out of Scope

- UI 展示（Phase 4/5/6）
- 具体业务逻辑（诗词背诵/口算判定）

## Dependencies

- **上游**：Phase 0（Flutter 项目脚手架、Hive 依赖已加入）+ Phase 1（assets JSON 已产出）
- **下游**：Phase 4/5/6 全部依赖本 Phase 的 Repository 和 Provider
