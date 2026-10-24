# Textbook PDF Draft Extractor

This local-only tool extracts page-level text from a PDF and emits an
unreviewed draft plus a quality report. It does not decide a book edition,
run OCR, or publish content into the Flutter app.

Structured course preparation is the next stage: see [COURSE_SCHEMA.md](COURSE_SCHEMA.md)
for the shared Dart schema, source-linked units/lessons, pinyin, vocabulary,
recitation ranges, exercises, per-node review, 12-volume matrix and publication
checks. Its `init/validate/review/worksheet/matrix/export` commands consume the
Python draft without changing its extraction contract.

## Setup

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
```

## Extract

```bash
python cli.py extract /path/to/book.pdf --output /tmp/book-draft.json
```

An optional JSON file can carry human-entered edition clues without approving
them as verified:

```json
{
  "publisher": "人民教育出版社",
  "grade": "六年级",
  "semester": "上册",
  "editionStatement": "版权页原文",
  "printingInformation": "印次原文",
  "evidenceNotes": "需与纸质书版权页复核"
}
```

Pass it with `--edition-metadata /path/to/edition.json`. The importer always
keeps `verificationStatus` as `unverified`.

The JSON stores both normal and layout-oriented text for each PDF page. The
layout mode is experimental and does not guarantee correct reading order. The
Markdown report lists pages needing manual inspection and possible OCR. An
unmapped font placeholder such as `(cid:123)` is flagged for review even if its
ASCII representation exceeds the low-text threshold. Counts use the larger of
the normal/layout results so the same extraction is not counted twice. An
existing output is never overwritten unless `--force` is supplied.
The PDF hash is checked again before output; if the source changes while it is
being read, extraction stops without writing a draft. Output JSON/report paths
must be separate from the source PDF and optional edition metadata file.

All edition and content review statuses remain `unverified` / `draft`. Keep
copyrighted source PDFs and generated full-book text out of the repository.

## Tests

```bash
python -m unittest discover -s tests
```
