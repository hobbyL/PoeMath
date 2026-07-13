# Data Pipeline — Poem Importer CLI

> Executable contracts for the `tools/poem_importer/` Dart CLI tool.

---

## 1. Scope

The poem importer is a standalone Dart CLI that transforms YAML source data into JSON assets consumed by the Flutter app. It is the single source of truth for all static poem/author/formula data.

---

## 2. Architecture

```
tools/poem_importer/data/sources/
  poems_core.yaml      → assets/data/poems_core.json     (130 poems, human-curated)
  poems_extended.yaml   → assets/data/poems_extended.json  (230 poems, semi-auto)
  poems_explore.yaml    → assets/data/poems_explore.json   (652 poems, fully auto)
  textbook_index.yaml   → (reference only, not exported)
                        → assets/data/authors.json         (23 authors)
                        → assets/data/formulas.json        (34 formulas)
```

### Three-Layer Design

| Layer | YAML prefix | ID prefix | Target | Actual | Quality |
|-------|------------|-----------|--------|--------|---------|
| Core | `poems_core.yaml` | `poem_core_` | ≥130 | 130 | Human-curated: full pinyin, annotations, translation, appreciation |
| Extended | `poems_extended.yaml` | `poem_ext_` | ≥400 | 230 | Semi-auto: annotations + translation complete, pinyin auto-generated |
| Explore | `poems_explore.yaml` | `poem_exp_` | ≥500 | 652 | Fully auto: annotations + translation complete, pinyin auto-generated |

---

## 3. CLI Commands

```bash
# Import specific layer
dart run tools/poem_importer/bin/poem_importer.dart import-core
dart run tools/poem_importer/bin/poem_importer.dart import-extended
dart run tools/poem_importer/bin/poem_importer.dart import-explore

# Import all layers + authors + formulas
dart run tools/poem_importer/bin/poem_importer.dart import-all

# Validate all JSON outputs
dart run tools/poem_importer/bin/poem_importer.dart validate
```

---

## 4. Data Contracts

### Poem JSON Schema (output)

```json
{
  "id": "poem_core_001",
  "title": "静夜思",
  "author": "李白",
  "dynasty": "唐",
  "content": "床前明月光，...",
  "pinyin": "chuáng qián míng yuè guāng ， ...",
  "annotations": [{"word": "举头", "meaning": "抬头"}],
  "translation": "...",
  "appreciation": "...",
  "background": "...",
  "famous_lines": ["举头望明月，低头思故乡"],
  "tags": ["思乡", "月亮"],
  "difficulty": 1,
  "grade": 1,
  "semester": "下",
  "textbook_unit": "课文8",
  "is_required": true
}
```

### Required fields (all layers)

| Field | Core | Extended | Explore |
|-------|------|----------|---------|
| id, title, author, dynasty | ✅ | ✅ | ✅ |
| content | ✅ | ✅ | ✅ |
| pinyin | ✅ manual or auto | ✅ auto-generated | ✅ auto-generated |
| annotations | ✅ | ✅ | ✅ |
| translation | ✅ | ✅ | ✅ |
| appreciation | ✅ | optional | optional |
| grade/semester/textbook_unit | ✅ | optional | optional |
| is_required | ✅ | optional | optional |
| tags | ✅ | ✅ | ✅ |
| difficulty | ✅ | ✅ | ✅ |

---

## 5. Pinyin Auto-Generation

The importer uses `lpinyin` with custom overrides for classical Chinese polyphonic characters:

- **Word-level overrides** (`_wordOverrides`): multi-char phrases like "行宫" → "xíng gōng"
- **Character-level overrides** (`_charOverrides`): single chars like "斜" → "xiá" in poetry context
- If YAML source has a `pinyin` field, it is used as-is (Core layer)
- If YAML source has empty/missing `pinyin`, it is auto-generated (Extended/Explore)

Location: `tools/poem_importer/lib/src/pipeline/pinyin_generator.dart`

---

## 6. Validation

`validate` command checks:
- All required fields present
- Pinyin syllable count matches content character count (warnings only)
- Grade in 1-6 range
- No duplicate IDs
- JSON parseable

Output: `build/data_validation_report.txt`

Current status: **0 errors, 3 warnings** (2 pinyin count mismatches due to punctuation, 1 Extended count below plan)

---

## 7. Common Mistakes

### Don't: Edit JSON output files directly
JSON files in `assets/data/` are generated. Edit the YAML sources, then run `import-all`.

### Don't: Use yaml.dump() formatting as reference
Python `yaml.dump()` reformats YAML differently from hand-written style. The importer handles both formats correctly.

### Gotcha: Duplicate titles across layers
When migrating poems between layers, always remove from source layer and update ID prefix. Use `grep` to check for duplicates before adding.

### Gotcha: Pinyin for punctuation
Chinese punctuation (，。！？) is preserved in pinyin output but not counted as syllables. This causes "syllable count != char count" warnings that are safe to ignore.

---

## 8. Data Completeness Summary (2026-07-13)

| Asset | Count | Annotations | Pinyin | Translation | Size |
|-------|-------|-------------|--------|-------------|------|
| Core | 130 | 130/130 ✅ | 130/130 ✅ | 130/130 ✅ | 212 KB |
| Extended | 230 | 230/230 ✅ | 230/230 ✅ | 230/230 ✅ | 490 KB |
| Explore | 652 | 652/652 ✅ | 652/652 ✅ | 652/652 ✅ | 941 KB |
| Authors | 23 | — | — | — | 9 KB |
| Formulas | 34 | — | — | — | 18 KB |
| **Total** | **1012 poems** | **100%** | **100%** | **100%** | **1.63 MB** |
