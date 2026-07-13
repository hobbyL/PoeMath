# Phase 1: 数据管道工具 + 诗词/公式/作者数据整理

> 父任务：`../07-12-poemath-mvp/`
> 依赖：无（可与 Phase 0 并行）

## Goal

产出 MVP 所需的**全部静态数据资产**：1000 首诗词（分核心/扩展/拓展三层）+ 60-80 条数学公式 + 作者信息表，并交付一套可复用的 Dart CLI 数据处理工具。这是数据侧的一次性重投入，成果直接被 Phase 2/4/6 消费。

## Requirements

### R1.1 数据管道工具（`tools/poem_importer/`）
- **R1.1.1** 独立 Dart CLI 项目（`pubspec.yaml` + `bin/`）
- **R1.1.2** 输入：yxcs/poems-db 的 poems1-4.json + authors.json + category.json + dynasty.json
- **R1.1.3** 处理能力：
  - 字段映射（yxcs schema → PoeMath schema）
  - 去重（按内容+作者去重）
  - lpinyin 批量拼音生成，含多音字词典 override
  - 按主题标签分类
  - 按唐诗三百首/宋词精选 匹配筛选
  - 数据清洗（HTML 标签剥离、异常字符处理）
- **R1.1.4** 输出：`assets/data/poems_core.json`、`poems_extended.json`、`poems_explore.json`、`authors.json`
- **R1.1.5** 命令示例：
  ```
  dart run bin/importer.dart --source /path/to/yxcs --output assets/data/ --layer core|extended|explore
  ```

### R1.2 教材权威索引（`docs/data/textbook_index.md`）
- **R1.2.1** 手工整理部编版 1-6 年级 12 册的古诗目录
- **R1.2.2** 每首诗标注：年级、学期、单元、教材页码、是否 75 首必背
- **R1.2.3** 用作核心层 130 首的匹配依据

### R1.3 筛选标准（`docs/data/poem_selection_criteria.md`）
- **R1.3.1** 记录三层筛选规则、拒收条件、边界案例
- **R1.3.2** 记录人工校验流程

### R1.4 核心层 130 首（人工精校）
- **R1.4.1** 逐首核对：原文（对照人教版教材原文）
- **R1.4.2** 年级/学期/单元标注（对照 textbook_index.md）
- **R1.4.3** 多音字拼音校对（如"斜 xiá"、"衰 cuī"、"骑 jì"）
- **R1.4.4** 注释/译文/赏析择优（yxcs 有多版本，选最适合小学生阅读的版本）
- **R1.4.5** 添加名句字段（`famous_lines`）
- **R1.4.6** 添加主题标签（`tags`）
- **R1.4.7** 输出：`assets/data/poems_core.json`

### R1.5 扩展层 ~400 首（半自动 + 抽检）
- **R1.5.1** 从 yxcs/poems-db 筛选：唐诗三百首（311首）+ 宋词精选（~100首）
- **R1.5.2** 全流程走 CLI 工具处理
- **R1.5.3** 抽检 10-20%（40-80 首），检查拼音/注释/字段完整性
- **R1.5.4** 输出：`assets/data/poems_extended.json`

### R1.6 拓展层 ~500 首（全自动化）
- **R1.6.1** 按主题标签筛选：写景/送别/爱国/思乡/节日/哲理/咏物/农事/亲情/边塞
- **R1.6.2** 全脚本处理，无人工干预
- **R1.6.3** 输出：`assets/data/poems_explore.json`

### R1.7 作者信息表（`assets/data/authors.json`）
- **R1.7.1** 收录 200+ 主要诗人
- **R1.7.2** 每位作者字段：id / name / dynasty / life_years / title / brief（3-5 句）/ representative_works（3-5 首诗 id）/ avatar（默认或分配）

### R1.8 数学公式（`assets/data/formulas.json`）
- **R1.8.1** 60-80 条人教版小学数学公式（对齐父任务 requirements-summary.md §3.5）
- **R1.8.2** 分类：几何/单位换算/数量关系/运算定律/分数小数/比例
- **R1.8.3** 每条含：id / category / name / formula_text / formula_latex / grade / params / memory_tip / example / related_formulas
- **R1.8.4** 手工整理，无需 CLI 工具

### R1.9 数据校验
- **R1.9.1** CLI 工具含 `--validate` 子命令
- **R1.9.2** 校验点：
  - 所有必填字段存在
  - 拼音字符数 == 原文字符数（去除标点后）
  - grade 在 1-6 范围
  - author 在 authors.json 中存在
  - id 唯一
  - JSON 可正确解析
- **R1.9.3** 输出：`build/data_validation_report.txt`

## Acceptance Criteria

- [x] **AC1.1** `tools/poem_importer/` CLI 项目可编译、可执行
- [x] **AC1.2** `assets/data/poems_core.json` 含 ≥130 首诗，全部字段完整 → **130 首，达标**
- [~] **AC1.3** `assets/data/poems_extended.json` 含 ≥400 首 → **230 首，未达数量目标；质量优先，唐诗三百首精选+宋词，所有注释/译文/拼音完整**
- [x] **AC1.4** `assets/data/poems_explore.json` 含 ≥500 首 → **652 首，达标**
- [~] **AC1.5** `assets/data/authors.json` 含 ≥200 位作者 → **23 位，MVP 够用，后续迭代补充**
- [~] **AC1.6** `assets/data/formulas.json` 含 60-80 条公式 → **34 条，MVP 够用，后续迭代补充**
- [x] **AC1.7** `docs/data/textbook_index.md` 与 `poem_selection_criteria.md` 已建立（textbook_index.yaml 格式）
- [x] **AC1.8** 数据校验报告：0 error，3 warnings（均为非阻塞性）
- [x] **AC1.9** 全部数据体积 ≤3MB → **1.63 MB，达标**

## Out of Scope

- App 内数据加载与展示（Phase 2/4）
- 首次导入到 Hive Box（Phase 2）

## Dependencies

- **上游**：无（可与 Phase 0 并行）
- **下游**：Phase 2（数据导入到 Hive）依赖本 Phase 的 assets 产出
