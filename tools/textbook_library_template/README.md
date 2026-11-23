# PoeMath Textbook Library

This directory is a starter template for the separate public repository
`hobbyL/PoeMath-Textbooks`. It contains metadata and tools only; no textbook PDF
is included.

Every file committed to a public repository, including older Git history, is
publicly accessible. Add only books that may be redistributed publicly. The
`downloadable` flag hides a title in PoeMath; it is not access control.

## Layout

```text
catalog.json
catalog.schema.json
books/<subject>/grade-<n>/<upper|lower>/<edition-id>.pdf
covers/<pdf-sha256>.webp
tools/validate_catalog.py
tools/requirements.txt
```

The template files are kept together here. When initializing the book
repository, copy their contents to its root and place the validator files in
`tools/`.

## Prepare and publish a book

1. Verify redistribution permission before adding the PDF to a public Git
   repository.
2. Create its permanent PDF path, then run:

   ```bash
   python3 tools/validate_catalog.py prepare --pdf books/math/grade-01/upper/pep-math-1a-2024.pdf
   ```

   This checks that PDFium can open the file and renders page 1 to a WebP cover.
   It prints the SHA-256, byte count, page count and cover hash.
3. Commit the PDF and generated cover. Do not replace files from an older
   edition.
4. Add a catalog record with its subject, grade, semester, title, publisher,
   edition facts, `sourcePath`, `coverPath` and redistribution evidence. Keep
   `downloadable` false until the record and source have been reviewed.
5. Pin the record to the commit containing both files, calculate the Git blob
   SHA, and update all file metadata:

   ```bash
   python3 tools/validate_catalog.py pin
   ```

6. Mark the record downloadable only after verifying the content and public
   redistribution basis. Run the complete check before committing `catalog.json`:

   ```bash
   python3 tools/validate_catalog.py check
   ```

The PDF/cover commit and catalog commit are separate because a commit cannot
contain its own hash. PoeMath reads `catalog.json` from `main` and downloads
each PDF from its immutable `sourceCommit` and `sourcePath`.

For local setup, create a virtual environment and install `tools/requirements.txt`.
The catalog validator never uploads or pushes files.
