# Structured textbook course schema v1

The PDF extraction draft and the course pack are different formats. Python
`cli.py extract` owns page extraction. `course.dart` creates/reviews course
drafts using the same pure-Dart decoder that future Flutter learning features
will consume: `lib/data/models/textbook_course.dart`.

## Commands

Run from the repository root; use the project's existing FVM dependencies.
No additional Python or Dart package is needed for the course commands.

```bash
# Extract pages first (using the importer Python virtual environment).
python tools/textbook_importer/cli.py extract /path/book.pdf --output /tmp/pages.json

# Create a new unreviewed pack, matched by exact PDF hash/size/page count.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart init \
  --draft /tmp/pages.json --catalog assets/data/textbook_catalog.json \
  --output /tmp/course.json

# Optionally add --toc /tmp/toc.json: the existing private TOC cache envelope.
# It supplies candidate unit/lesson order, NOT approved teaching requirements.

# Validate syntax/references; valid drafts exit 0 but report publishable:false.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart validate \
  --input /tmp/course.json --output /tmp/validation.json

# Assemble source-linked page text for comparison against the original PDF.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart worksheet \
  --input /tmp/course.json --draft /tmp/pages.json --output /tmp/review.md

# After actually inspecting this node's original pages and correcting its data:
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart review \
  --input /tmp/course.json --node paragraph-001 --reviewer 'Reviewer name' \
  --decision approved --checks sourcePages,content,pinyin \
  --notes 'Compared text and every pinyin token with the original page.' \
  --output /tmp/course-reviewed.json

# Review all applicable nodes individually, then review the pack with:
# --node @pack --checks coverage,content
# Rejection uses --decision rejected plus a reason. No bulk approval command.

# Strict release check: exits 2 for any review/coverage/permission blocker.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart validate \
  --input /tmp/course.json --for-publish

# Export only an already valid, fully reviewed and permitted pack.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart export \
  --input /tmp/course.json --output /tmp/course-release.json

# Reproducible 12-volume progress matrix, optionally add --drafts/--packs dirs.
~/.pub-cache/bin/fvm dart run tools/textbook_importer/course.dart matrix \
  --catalog assets/data/textbook_catalog.json --output /tmp/review-matrix.json
```

All JSON outputs require a new destination unless `--force` is supplied.
Input aliases, including symbolic/hard links, cannot be overwritten even with
`--force`. Files are written to a temporary sibling directory and renamed after
the complete write. Use one writer per destination. Real PDFs, full text and
interior-page images stay outside the repository and application assets.

## Root and edition

All listed fields are required. Unknown information uses explicit `null` where
allowed; unknown keys and unsupported schema versions are rejected.

| Field | Type / contract |
| --- | --- |
| `schemaVersion` / `kind` | `1` / `textbookCourse` |
| `status` | `draft` or `reviewed`; a status string alone never approves content |
| `contentRevision` | Positive integer; increment when revising a distributed pack |
| `coverage` | `partial` or `complete`; independent of review/permission |
| `expectedLessonCount` | Positive integer or null; complete packs must match the actual count |
| `edition` | Identity below |
| `permissions` | Separate `content` and `applicationUse`, each `{status,evidence}` |
| `review` | Pack-level review record |
| `units` / `lessons` | Ordered arrays, preserving the reviewed book's actual order |

Edition fields are `id`, `pdfSha256`, `pageCount`, `fileSize`, `title`, `grade`,
`semester`, `publisher`, `editionLabel`, `editionNotes`, `publicationDate`,
`editionNumber`, `printingDate`, `printingNumber`, `sourceUrl`, `sources`, `review`.
Grade is 1–6; semester is `上`/`下`; dates are `YYYY-MM` or null; edition/printing
numbers are positive integers or null. Source URL is HTTPS. Page count is 1–5000.
The generated edition ID includes grade, semester and the PDF hash prefix.
Unknown publication details remain null; PDF creation dates prove nothing.

All edition/unit/lesson/target IDs match `[a-z][a-z0-9._-]{0,127}` and are unique
within the pack. Later learning facts use `edition.id + target.id`, never a
poem ID or title. `init` creates initial IDs only. Preserve IDs while editing;
do not regenerate an existing published pack from a changed TOC.

## Source pages and reviews

Every node has `sources` and `review`. A source entry has:

```json
{
  "pdfPage": 7,
  "printedPage": "2",
  "extractionStatus": "text_extracted"
}
```

`pdfPage` is the physical, 1-based page in this exact PDF. `printedPage` is a
nonempty string or null (Roman numerals/appendix labels are allowed). It is
never calculated using one universal offset. `extractionStatus` preserves
`text_extracted`, `no_text`, `low_text`, `replacement_characters`,
`cid_placeholders`, `extraction_error`, or `manual` for directly entered data.
Extraction status is independent of human review. Empty sources are allowed
in a draft for unresolved TOC nodes, but block publication.

```json
{
  "status": "unreviewed",
  "reviewer": null,
  "reviewedAt": null,
  "contentSha256": null,
  "checks": [],
  "notes": null
}
```

Review status is `unreviewed`, `approved`, or `rejected`. A decision requires
reviewer, ISO timestamp with timezone and SHA-256. Approval also requires the
node's checks below and a current digest. The CLI records the explicit human
decision; it does not infer approval from successful extraction, a TOC, a model
response, or a book-matching flag.

| Node | Required checks |
| --- | --- |
| Edition | `sourcePages,edition` |
| Unit | `sourcePages,content` |
| Lesson | `sourcePages,content,coverage` |
| Paragraph | `sourcePages,content`, plus `pinyin` if present |
| Vocabulary | Paragraph checks plus `requirement` |
| Recitation | `sourcePages,content,range` |
| Exercise | `sourcePages,content,answer` (including deliberate absence of an answer) |
| Whole pack | `coverage,content`; all content blockers must already be resolved |

Digests use sorted-key JSON with review records recursively omitted. Every node
digest also includes edition ID, PDF SHA, byte size and page count. Changing a
source, text, pinyin, requirement, answer or range invalidates that node's review
and its containing lesson/pack review. Switching editions/PDFs invalidates all
node reviews. This guards accidental stale approval; it is not a digital
signature or proof that a human actually inspected a page.

## Units and lessons

Unit fields: `id,title,sources,review,lessonIds`. Each lesson must appear exactly
once in a unit, with a matching `unitId`; missing and duplicate references fail.

Lesson fields: `id,unitId,title,kind,lessonNumber,sources,review,coverage`, and six
arrays: `paragraphs,recognitionCharacters,writingCharacters,words,recitations,exercises`.
`lessonNumber` is a positive integer or null; numbering may restart in another
unit. `kind` is `text,literacy,poetry,classical,oral,writing,garden,reading,appendix,other`.
TOC-seeded values remain `other` until reviewed. A level-0 appendix starts a new
candidate group rather than being attached to the previous teaching unit.

The lesson's `coverage` object has one entry for each of the six array names:

- `pending`: requirements or completeness have not been checked, even if some
  candidate data exists. Blocks publication.
- `notApplicable`: reviewer checked there is no such requirement; array is empty.
- `complete`: reviewer checked this category; array must contain targets.

An empty array never silently means “the book has no requirement”. A partial
pack may cover selected, fully checked lessons, without claiming book coverage.

## Paragraphs and vocabulary

Paragraph fields: `id,text,pinyin,sources,review`. `text` is nonempty; `pinyin`
is null or an array with one token per **non-whitespace Unicode scalar value**.
Punctuation must occupy its exact original token. Han readings use lowercase
tone-marked pinyin or lowercase numbered pinyin; broken extraction codes such
as `chOn` are rejected. Alignment and format checks cannot prove the correct
reading of a polyphonic character: that remains a source-review decision.

Vocabulary adds `requirement`:

- `recognitionCharacters`: one Han character, `requirement:recognition`.
- `writingCharacters`: one Han character, `requirement:writing`.
- `words`: `requirement:reading` or `dictation`. A word's presence in a passage
  does not establish a dictation requirement.

Published vocabulary must include reviewed pinyin. The same character may be a
recognition and writing target, using different stable IDs and requirements.

## Recitation and exercises

Recitation fields: `id,instruction,ranges,sources,review`. `instruction` retains
the actual requirement; `ranges` is nonempty. Each range contains:

```json
{"paragraphId":"paragraph-001","start":0,"end":2,"textSha256":"SHA-256 of the selected text"}
```

Ranges are half-open Unicode-scalar offsets into the **raw paragraph including
whitespace**, not UTF-16 code units. They must refer to this lesson's paragraphs,
be nonempty and within bounds, and must not overlap. The selected text's hash
must match, so editing a referenced paragraph cannot silently move the target.
Whole-text recitation explicitly lists each covered paragraph/range.

Exercise fields: `id,prompt,origin,answerType,answers,answerOrigin,answerSources,sources,review`.
Optional `promptLayout` preserves reading-exercise rows and columns as
`[[{"text":"word","emphasis":[0]}]]`. `emphasis` contains unique zero-based
Unicode-scalar positions of characters with dots underneath. Cells contain no
newlines or tabs; joining cells with tabs and rows with newlines must exactly
equal `prompt`. Old packs can omit this field. Editing prompt text clears a
previous layout unless a matching replacement is explicitly supplied; editing
answers preserves it. Layout and emphasis participate in content review hashes.
`origin` is `textbook` or `curated`. Answer types are `none`, `exact`, `reference`,
or `parentCheck`. `exact`/`reference` require nonempty answers; `none` has no
answers. `answerOrigin` is `none`, `textbook`, or `reviewerReference`; textbook
answers require their own original page sources. Reviewer references may be
used as reference points or with parent checking, but cannot be labeled exact
standard answers. No answer is invented when the book only gives an open task.

## Publication and the 12-volume matrix

`TextbookCoursePack.fromJson` validates draft syntax, types, identities, pinyin,
references, ranges and answer consistency. `publicationIssues` lists all
remaining review/coverage/permission blockers. `forPublication` and CLI `export`
reject any blockers. Both permissions must be `permitted` with nonempty evidence;
`unknown`/`prohibited` never pass merely because the source is publicly reachable.

The matrix requires 12 unique grade/semester volumes and exact PDF matches for
provided drafts/packs. It records source evidence, extraction, directory hints,
lesson/target review, scope, permissions and publication separately. Missing
files mean `notRecorded`/`notStarted`, never “all audited”. The committed
`data/review_matrix.json` contains metadata only; regenerate from current local
drafts/packs when recording progress. Full-book text is not part of that matrix.

`examples/synthetic-course.json` is a complete-field, unreviewed example made
from owned synthetic text. Tests call the actual builder/review/export pipeline
and decode its results; real-book samples and worksheets remain under `/tmp`.
This slice provides content preparation/review infrastructure. App lesson pages,
dictation, recitation and learning-fact persistence belong to the next slice.


## In-app editing and review

Settings → book management → textbook detail → content review (fact-check icon).
Import a course JSON for this exact PDF hash/size/page count and grade/semester.
Replacing an existing local draft requires explicit confirmation. The app lists
units, lessons and all six content categories; individual items support editing,
source-page comparison, explicit checklists and reviewer/notes before approval
or rejection. Lesson coverage is confirmed separately, never inferred from an
empty array. Missing targets still require supplementing the draft and importing
it again; the app edits existing items rather than creating a whole curriculum.

`lib/data/models/textbook_course_review.dart` now owns shared review/edit
operations; the CLI re-exports its original review API. Content edits increment
`contentRevision`, reset the edited item's and whole pack's review, and make
content-dependent reviews stale. Paragraph edits recompute bound recitation
text digests at the same character positions and clear recitation reviews;
if a range would exceed the new text, editing fails with an instruction to
adjust the range first. The UI previews exact selected characters.

App drafts live in the private `textbooks/courses/<pdfSha256>.json` directory,
independent of rebuildable PDF caches. They survive removing/reimporting the
PDF, remain unencrypted locally, and are excluded from JSON/WebDAV backups.
Last-decision reviewer/time/checks/notes persist; this is not an append-only
audit history. Saving compares the prior complete pack to the current file,
rejecting stale pages, and renames an atomically completed sibling file.
No review operation writes a child's reading progress or unlocks a learning
feature. Unknown permissions continue to block publication.
