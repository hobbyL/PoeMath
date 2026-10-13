# poem_importer

PoeMath 数据管道 CLI 工具。将 `data/sources/` 下的手工整理 YAML 转换为
`assets/data/` 下的运行时 JSON 资产。

## 目标

对齐父任务 `.trellis/tasks/07-12-poemath-mvp/design.md` §7 中的数据管道设计：

- 输入：手工整理的 YAML（`poems_core.yaml`、`poems_extended.yaml`、
  `poems_explore.yaml`、`authors_seed.yaml`、`formulas.yaml`）
- 处理：字段规范化 / lpinyin 拼音生成（含多音字覆盖表）/ layer 标注
- 输出：符合 App 端 Hive/JSON schema 的 5 个资产文件

## 安装

本包是**独立 Dart 包**（不在项目根 pubspec 的依赖里），有自己的 `pubspec.yaml`
与 `.dart_tool/`。子包 `.dart_tool/` 被 `.gitignore` 忽略，因此**冷环境
（新克隆、`flutter clean` 之后）必须先初始化子包依赖**，否则命令会因包解析失败
而编译不过。

```bash
cd tools/poem_importer
dart pub get
```

依赖：`args`、`yaml`、`lpinyin`。开发依赖 `test`、`lints`。

> **常见故障**：跳过上面的 `pub get`、直接从项目根执行时，会报
> `The method 'AuthorsImporter' isn't defined`（`FormulasImporter` /
> `SchemaValidator` 同理，仅在 `import-all` 与 `validate` 出现）。
>
> 原因是根包的 `.dart_tool/package_config.json` 里没有 `poem_importer` 的自引用，
> `package:poem_importer/...` 解析不到，barrel 导出全部失效。执行一次
> `cd tools/poem_importer && dart pub get` 即修复。

## 使用

**必须从项目根目录执行** —— 默认路径 `tools/poem_importer/data/sources` 与
`assets/data` 是相对项目根硬编码的（`bin/poem_importer.dart` 的
`_kDefaultSourceDir` / `_kDefaultOutputDir`）。在工具目录内直接跑会找不到
输入与产物目录（除非显式传 `--source-dir` / `--output-dir`）。

```bash
cd <项目根>
dart run tools/poem_importer/bin/poem_importer.dart <command>
```

### 可用子命令

| 命令 | 说明 |
|------|------|
| `import-core`      | 从 `data/sources/poems_core.yaml` 生成 `assets/data/poems_core.json` |
| `import-extended`  | 从 `data/sources/poems_extended.yaml` 生成 `assets/data/poems_extended.json` |
| `import-explore`   | 从 `data/sources/poems_explore.yaml` 生成 `assets/data/poems_explore.json` |
| `import-authors`   | 从 `data/sources/authors_seed.yaml` 生成 `assets/data/authors.json` |
| `import-formulas`  | 从 `data/sources/formulas.yaml` 生成 `assets/data/formulas.json` |
| `import-all`       | 依次执行上述 5 个 importer |
| `validate`         | 校验 `assets/data/*.json` 的字段完整性 / 拼音字数一致性 / id 唯一性 |

### 参数

所有 `import-*` 命令支持：

- `--source, -s`  覆盖默认的 YAML 输入路径
- `--output, -o`  覆盖默认的 JSON 输出路径

`import-all` / `validate` 支持：

- `--source-dir` / `--output-dir` / `--asset-dir` / `--report`

### 示例

```bash
# 一次性生成全部 5 个资产
dart run tools/poem_importer/bin/poem_importer.dart import-all

# 只生成核心层
dart run tools/poem_importer/bin/poem_importer.dart import-core

# 校验生成的资产（写入 build/data_validation_report.txt）
dart run tools/poem_importer/bin/poem_importer.dart validate
```

## 目录结构

```
tools/poem_importer/
├── bin/
│   └── poem_importer.dart        CLI 入口
├── lib/
│   ├── poem_importer.dart        公共导出
│   └── src/
│       ├── io/                   YAML 读取 / JSON 写入
│       ├── models/               Poem / Author / Formula / Annotation
│       ├── pipeline/             各 importer + 拼音生成器
│       └── validator/            schema 校验
├── data/sources/                 人工整理 YAML 源
├── pubspec.yaml
└── README.md
```

## 拼音多音字策略

拼音生成分三层：

1. **词组覆盖**（`_wordOverrides`）— 例如 "石径斜" → `shí jìng xiá`
2. **单字覆盖**（`_charOverrides`）— 例如 "朝辞" 的 "朝" → `zhāo`
3. **lpinyin 默认**（带声调 `WITH_TONE_MARK`）

新增多音字场景时，直接在 `lib/src/pipeline/pinyin_generator.dart` 的两个字典中追加即可。

## 当前数据规模

| 源文件 | 条数 | 产物 |
|---|---|---|
| `poems_core.yaml` | 130 | `poems_core.json`（核心层，课标必背） |
| `poems_extended.yaml` | 400 | `poems_extended.json`（扩展层） |
| `poems_explore.yaml` | 501 | `poems_explore.json`（探索层，主题标签驱动） |
| `authors_seed.yaml` | 383 | `authors.json` |
| `formulas.yaml` | 65 | `formulas.json` |

诗词合计 1031 首。`data/sources/textbook_index.yaml` 是**编纂参考**（部编版
1-6 年级教材古诗目录，供人工查对篇目/必背标记），不被任何 importer 读取，
不产出资产。

## 数据变更后

改动 YAML 后必须重跑 importer 并校验：

```bash
dart run tools/poem_importer/bin/poem_importer.dart import-all
dart run tools/poem_importer/bin/poem_importer.dart validate
```

注意 App 端 `lib/data/hive/bootstrap.dart` 以 `AppConstants.dataVersion` 为
依据决定是否重新导入资产 —— 只改 YAML 而不同步提升该版本号，已安装的 App
会跳过导入、看不到新数据。
