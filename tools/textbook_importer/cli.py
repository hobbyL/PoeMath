"""Extract page-level PDF text into a local, unreviewed draft."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pdfplumber
from pdfminer.pdfexceptions import PDFException

TOOL_VERSION = "0.1.0"
DEFAULT_LOW_TEXT_THRESHOLD = 24
CID_PLACEHOLDER_PATTERN = re.compile(r"\(cid:\d+\)")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _metadata_as_strings(metadata: Any) -> dict[str, str]:
    if not isinstance(metadata, dict):
        return {}
    return {
        str(key): str(value) for key, value in metadata.items() if value is not None
    }


def _page_record(
    page_number: int, page: Any, low_text_threshold: int
) -> dict[str, Any]:
    errors: list[str] = []
    try:
        text = page.extract_text() or ""
    except Exception as error:  # noqa: BLE001 - isolate parser failures to one page
        text = ""
        errors.append(f"plain text extraction failed: {type(error).__name__}: {error}")
    try:
        layout_text = page.extract_text(layout=True) or ""
    except Exception as error:  # noqa: BLE001 - isolate parser failures to one page
        layout_text = ""
        errors.append(f"layout extraction failed: {type(error).__name__}: {error}")
    non_whitespace_count = sum(not character.isspace() for character in text)
    replacement_count = max(text.count("\ufffd"), layout_text.count("\ufffd"))
    cid_placeholder_count = max(
        len(CID_PLACEHOLDER_PATTERN.findall(text)),
        len(CID_PLACEHOLDER_PATTERN.findall(layout_text)),
    )
    needs_review = (
        non_whitespace_count < low_text_threshold
        or replacement_count > 0
        or cid_placeholder_count > 0
        or bool(errors)
    )

    if errors:
        extraction_status = "extraction_error"
    elif non_whitespace_count == 0:
        extraction_status = "no_text"
    elif replacement_count > 0:
        extraction_status = "replacement_characters"
    elif cid_placeholder_count > 0:
        extraction_status = "cid_placeholders"
    elif non_whitespace_count < low_text_threshold:
        extraction_status = "low_text"
    else:
        extraction_status = "text_extracted"

    return {
        "pdfPageNumber": page_number,
        "width": float(page.width),
        "height": float(page.height),
        "text": text,
        "layoutText": layout_text,
        "nonWhitespaceCharacterCount": non_whitespace_count,
        "replacementCharacterCount": replacement_count,
        "cidPlaceholderCount": cid_placeholder_count,
        "extractionStatus": extraction_status,
        "ocrReviewSuggested": needs_review,
        "extractionErrors": errors,
    }


def extract_draft(
    pdf_path: Path,
    *,
    low_text_threshold: int = DEFAULT_LOW_TEXT_THRESHOLD,
) -> dict[str, Any]:
    if low_text_threshold < 1:
        raise ValueError("low_text_threshold must be greater than zero")
    if not pdf_path.is_file():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")
    original_hash = sha256_file(pdf_path)
    original_size = pdf_path.stat().st_size

    pages: list[dict[str, Any]] = []
    with pdfplumber.open(str(pdf_path)) as pdf:
        metadata = _metadata_as_strings(pdf.metadata)
        for page_number, page in enumerate(pdf.pages, start=1):
            pages.append(_page_record(page_number, page, low_text_threshold))
            page.close()

    if sha256_file(pdf_path) != original_hash:
        raise ValueError("PDF changed during extraction; no draft was written")

    review_pages = [
        page["pdfPageNumber"] for page in pages if page["ocrReviewSuggested"]
    ]
    summary = {
        "pageCount": len(pages),
        "pagesWithText": sum(page["nonWhitespaceCharacterCount"] > 0 for page in pages),
        "pagesNeedingReview": review_pages,
        "pagesWithErrors": [
            page["pdfPageNumber"] for page in pages if page["extractionErrors"]
        ],
        "pagesWithReplacementCharacters": [
            page["pdfPageNumber"]
            for page in pages
            if page["replacementCharacterCount"] > 0
        ],
        "pagesWithCidPlaceholders": [
            page["pdfPageNumber"] for page in pages if page["cidPlaceholderCount"] > 0
        ],
        "totalNonWhitespaceCharacterCount": sum(
            page["nonWhitespaceCharacterCount"] for page in pages
        ),
        "totalReplacementCharacterCount": sum(
            page["replacementCharacterCount"] for page in pages
        ),
        "totalCidPlaceholderCount": sum(page["cidPlaceholderCount"] for page in pages),
        "lowTextThreshold": low_text_threshold,
    }

    return {
        "schemaVersion": 1,
        "status": "draft",
        "editionVerificationStatus": "unverified",
        "contentReviewStatus": "unreviewed",
        "source": {
            "fileName": pdf_path.name,
            "fileSizeBytes": original_size,
            "sha256": original_hash,
            "pdfMetadata": metadata,
        },
        "editionDraft": {
            "metadata": {},
            "verificationStatus": "unverified",
        },
        "extractor": {
            "name": "pdfplumber",
            "version": pdfplumber.__version__,
            "toolVersion": TOOL_VERSION,
            "generatedAtUtc": datetime.now(UTC).isoformat(),
            "ocrPerformed": False,
        },
        "qualitySummary": summary,
        "pages": pages,
    }


def render_report(draft: dict[str, Any]) -> str:
    source = draft["source"]
    summary = draft["qualitySummary"]
    review_pages = summary["pagesNeedingReview"]
    review_list = ", ".join(str(page) for page in review_pages) or "无"
    replacement_pages = summary.get("pagesWithReplacementCharacters", [])
    cid_pages = summary.get("pagesWithCidPlaceholders", [])
    return "\n".join(
        [
            "# PDF 抽取质量报告",
            "",
            f"- 文件：`{source['fileName']}`",
            f"- SHA-256：`{source['sha256']}`",
            f"- 页数：{summary['pageCount']}",
            f"- 有文本页：{summary['pagesWithText']}",
            f"- 非空白字符：{summary['totalNonWhitespaceCharacterCount']}",
            f"- 替换字符：{summary['totalReplacementCharacterCount']}",
            f"- 含替换字符页：{', '.join(str(page) for page in replacement_pages) or '无'}",
            f"- 未解码 CID 字形：{summary.get('totalCidPlaceholderCount', 0)}",
            f"- 含未解码 CID 字形页：{', '.join(str(page) for page in cid_pages) or '无'}",
            f"- 需人工检查/可能需 OCR 的页：{review_list}",
            f"- 抽取异常页：{', '.join(str(page) for page in summary.get('pagesWithErrors', [])) or '无'}",
            "- 版次核验：未核",
            "- 内容审核：未审核（草稿，不可发布）",
            "",
            "低文本页也可能是封面、插图或留白；请对照原页确认，不能仅凭该标记判定需要 OCR。",
            "",
        ]
    )


def _write_atomic(path: Path, content: str, *, force: bool) -> None:
    if path.exists() and not force:
        raise FileExistsError(
            f"Output already exists: {path}; use --force to replace it"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        if force:
            os.replace(temporary_path, path)
        else:
            # Publishing by link fails atomically if another writer created path.
            os.link(temporary_path, path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def _extract_command(args: argparse.Namespace) -> int:
    pdf_path = Path(args.pdf)
    output_path = Path(args.output)
    if output_path.suffix.lower() != ".json":
        raise ValueError("Output path must end with .json")
    report_path = output_path.with_suffix(".report.md")
    input_paths = [pdf_path]
    if args.edition_metadata is not None:
        input_paths.append(Path(args.edition_metadata))
    for destination in (output_path, report_path):
        for source in input_paths:
            same_path = destination.resolve() == source.resolve()
            same_file = (
                destination.exists()
                and source.exists()
                and destination.samefile(source)
            )
            if same_path or same_file:
                raise ValueError(f"Output must not overwrite an input file: {source}")
    if not args.force and (output_path.exists() or report_path.exists()):
        raise FileExistsError(
            f"Output already exists: {output_path} or {report_path}; use --force to replace it"
        )

    edition_metadata: dict[str, Any] = {}
    if args.edition_metadata is not None:
        try:
            loaded_metadata = json.loads(
                Path(args.edition_metadata).read_text(encoding="utf-8")
            )
        except json.JSONDecodeError as error:
            raise ValueError(f"Invalid edition metadata JSON: {error}") from error
        if not isinstance(loaded_metadata, dict):
            raise ValueError("Edition metadata JSON must contain an object")
        allowed_fields = {
            "publisher",
            "grade",
            "semester",
            "editionStatement",
            "printingInformation",
            "evidenceNotes",
        }
        unknown_fields = set(loaded_metadata) - allowed_fields
        if unknown_fields:
            raise ValueError(
                "Unsupported edition metadata fields: "
                + ", ".join(sorted(unknown_fields))
            )
        if any(not isinstance(value, str) for value in loaded_metadata.values()):
            raise ValueError("Edition metadata values must be strings")
        edition_metadata = loaded_metadata

    draft = extract_draft(pdf_path, low_text_threshold=args.low_text_threshold)
    draft["editionDraft"]["metadata"] = edition_metadata
    _write_atomic(
        output_path,
        json.dumps(draft, ensure_ascii=False, indent=2) + "\n",
        force=args.force,
    )
    _write_atomic(report_path, render_report(draft), force=args.force)

    summary = draft["qualitySummary"]
    print(
        f"Extracted {summary['pageCount']} pages; "
        f"{len(summary['pagesNeedingReview'])} need review."
    )
    print(f"Draft: {output_path}")
    print(f"Report: {report_path}")
    print("Edition: unverified; content: unreviewed.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract local textbook PDF text into an unreviewed draft."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    extract = subparsers.add_parser("extract", help="extract text page by page")
    extract.add_argument("pdf", help="path to a local PDF")
    extract.add_argument("--output", required=True, help="path for draft JSON")
    extract.add_argument(
        "--low-text-threshold",
        type=int,
        default=DEFAULT_LOW_TEXT_THRESHOLD,
        help=f"flag pages with fewer than this many non-space characters (default: {DEFAULT_LOW_TEXT_THRESHOLD})",
    )
    extract.add_argument(
        "--edition-metadata",
        help="optional JSON object with publisher/grade/semester/edition evidence notes",
    )
    extract.add_argument(
        "--force", action="store_true", help="replace an existing JSON/report pair"
    )
    extract.set_defaults(handler=_extract_command)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.handler(args)
    except (PDFException, OSError, ValueError, TypeError) as error:
        print(f"Extraction failed ({type(error).__name__}): {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
