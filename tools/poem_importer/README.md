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

```bash
cd tools/poem_importer
dart pub get
```

依赖：`args`、`yaml`、`lpinyin`。开发依赖 `test`、`lints`。

## 使用

```bash
# 从项目根目录执行（默认路径已按此假设配置）
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

## Phase 1 交付边界

本次 Phase 1 交付：

- CLI 工具全套（可编译、可执行）
- 30 首核心层示例诗词（真实课标篇目）
- 10-15 首扩展层 + 5-10 首拓展层示例
- 20+ 作者信息
- 32 条公式示例（目标 60-80，Phase 1 结束前继续补齐）

后续 Phase 需要扩充数据到 130 / 400 / 500 / 200 / 60-80 的完整规模，工具本身不需改动。
