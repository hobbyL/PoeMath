import hashlib
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cli


def missing_unicode_pdf_bytes():
    """Build a content-free PDF fixture with undecodable Type0 font glyphs."""
    stream = b"BT /F1 12 Tf 20 700 Td <000100020003000400050006> Tj ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
            b"/Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R >>"
        ),
        (
            b"<< /Type /Font /Subtype /Type0 /BaseFont /Missing /Encoding /Identity-H "
            b"/DescendantFonts [5 0 R] >>"
        ),
        (
            b"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Missing "
            b"/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> "
            b"/FontDescriptor << /Type /FontDescriptor /FontName /Missing /Flags 4 "
            b"/FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0 "
            b"/CapHeight 1000 /StemV 80 >> /DW 1000 >>"
        ),
        b"<< /Length "
        + str(len(stream)).encode()
        + b" >>\nstream\n"
        + stream
        + b"endstream",
    ]
    content = b"%PDF-1.4\n"
    offsets = []
    for number, pdf_object in enumerate(objects, start=1):
        offsets.append(len(content))
        content += str(number).encode() + b" 0 obj\n" + pdf_object + b"\nendobj\n"
    xref_offset = len(content)
    content += b"xref\n0 7\n0000000000 65535 f \n"
    for offset in offsets:
        content += f"{offset:010} 00000 n \n".encode()
    content += f"trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode()
    return content


class TextbookImporterTests(unittest.TestCase):
    def test_extract_draft_keeps_pages_hash_and_unreviewed_status(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            pdf_path = Path(temporary_dir) / "book.pdf"
            pdf_path.write_bytes(b"fixture-pdf-bytes")

            first_page = MagicMock()
            first_page.width = 595.0
            first_page.height = 842.0
            first_page.extract_text.side_effect = ["第一课 正文", "第一课\n正文"]
            second_page = MagicMock()
            second_page.width = 595.0
            second_page.height = 842.0
            second_page.extract_text.side_effect = [None, None]

            pdf = MagicMock()
            pdf.metadata = {"Title": "Test fixture"}
            pdf.pages = [first_page, second_page]
            with patch.object(cli.pdfplumber, "open") as open_pdf:
                open_pdf.return_value.__enter__.return_value = pdf
                draft = cli.extract_draft(pdf_path, low_text_threshold=4)

            self.assertEqual(
                draft["source"]["sha256"],
                hashlib.sha256(b"fixture-pdf-bytes").hexdigest(),
            )
            self.assertEqual(draft["qualitySummary"]["pageCount"], 2)
            self.assertEqual(draft["qualitySummary"]["pagesNeedingReview"], [2])
            self.assertEqual(draft["pages"][0]["pdfPageNumber"], 1)
            self.assertEqual(draft["pages"][1]["extractionStatus"], "no_text")
            self.assertEqual(draft["status"], "draft")
            self.assertEqual(draft["editionVerificationStatus"], "unverified")
            self.assertEqual(draft["contentReviewStatus"], "unreviewed")

    def test_page_extraction_error_is_recorded_without_aborting_other_pages(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            pdf_path = Path(temporary_dir) / "book.pdf"
            pdf_path.write_bytes(b"fixture-pdf-bytes")
            broken_page = MagicMock()
            broken_page.width = 595.0
            broken_page.height = 842.0
            broken_page.extract_text.side_effect = [RuntimeError("bad cmap"), ""]
            good_page = MagicMock()
            good_page.width = 595.0
            good_page.height = 842.0
            good_page.extract_text.side_effect = [
                "第二课正文内容足够超过低文本阈值",
                "第二课正文内容足够超过低文本阈值",
            ]
            pdf = MagicMock()
            pdf.metadata = {}
            pdf.pages = [broken_page, good_page]

            with patch.object(cli.pdfplumber, "open") as open_pdf:
                open_pdf.return_value.__enter__.return_value = pdf
                draft = cli.extract_draft(pdf_path, low_text_threshold=4)

            self.assertEqual(draft["qualitySummary"]["pagesWithErrors"], [1])
            self.assertEqual(draft["pages"][0]["extractionStatus"], "extraction_error")
            self.assertEqual(draft["pages"][1]["extractionStatus"], "text_extracted")

    def test_pdf_change_during_extraction_prevents_draft_creation(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            pdf_path = Path(temporary_dir) / "book.pdf"
            pdf_path.write_bytes(b"fixture-pdf-bytes")
            pdf = MagicMock()
            pdf.metadata = {}
            pdf.pages = []

            with (
                patch.object(cli.pdfplumber, "open") as open_pdf,
                patch.object(cli, "sha256_file", side_effect=["before", "after"]),
            ):
                open_pdf.return_value.__enter__.return_value = pdf
                with self.assertRaisesRegex(ValueError, "changed during extraction"):
                    cli.extract_draft(pdf_path)

    def test_cli_rejects_output_that_is_the_source_pdf(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            source_and_output = Path(temporary_dir) / "book.json"
            source_and_output.write_text("keep me", encoding="utf-8")
            args = cli.build_parser().parse_args(
                ["extract", str(source_and_output), "--output", str(source_and_output)]
            )

            with self.assertRaisesRegex(ValueError, "must not overwrite an input"):
                cli._extract_command(args)

            self.assertEqual(source_and_output.read_text(encoding="utf-8"), "keep me")

    def test_cli_does_not_overwrite_existing_report_without_force(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            source_pdf = Path(temporary_dir) / "book.pdf"
            source_pdf.write_bytes(b"fake-pdf")
            output = Path(temporary_dir) / "draft.json"
            report = output.with_suffix(".report.md")
            report.write_text("keep report", encoding="utf-8")
            args = cli.build_parser().parse_args(
                ["extract", str(source_pdf), "--output", str(output)]
            )

            with self.assertRaises(FileExistsError):
                cli._extract_command(args)

            self.assertFalse(output.exists())
            self.assertEqual(report.read_text(encoding="utf-8"), "keep report")

    def test_edition_metadata_is_stored_as_unverified_input(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            pdf_path = Path(temporary_dir) / "book.pdf"
            pdf_path.write_bytes(b"fixture-pdf-bytes")
            metadata_path = Path(temporary_dir) / "edition.json"
            metadata_path.write_text(
                json.dumps({"publisher": "人民教育出版社", "grade": "一年级"}),
                encoding="utf-8",
            )
            page = MagicMock()
            page.width = 595.0
            page.height = 842.0
            page.extract_text.return_value = "正文内容"
            pdf = MagicMock()
            pdf.metadata = {}
            pdf.pages = [page]

            with patch.object(cli.pdfplumber, "open") as open_pdf:
                open_pdf.return_value.__enter__.return_value = pdf
                args = cli.build_parser().parse_args(
                    [
                        "extract",
                        str(pdf_path),
                        "--output",
                        str(Path(temporary_dir) / "draft.json"),
                        "--edition-metadata",
                        str(metadata_path),
                    ]
                )
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(args.handler(args), 0)

            draft = json.loads(
                (Path(temporary_dir) / "draft.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                draft["editionDraft"]["metadata"]["publisher"], "人民教育出版社"
            )
            self.assertEqual(draft["editionDraft"]["verificationStatus"], "unverified")

    def test_replacement_characters_are_counted(self):
        page = MagicMock()
        page.width = 595.0
        page.height = 842.0
        page.extract_text.side_effect = ["正文�文本足够长", "正文�文本足够长"]

        record = cli._page_record(1, page, low_text_threshold=1)

        self.assertEqual(record["replacementCharacterCount"], 1)
        self.assertEqual(record["extractionStatus"], "replacement_characters")
        self.assertTrue(record["ocrReviewSuggested"])

    def test_report_does_not_call_empty_pages_ocr_results(self):
        report = cli.render_report(
            {
                "source": {"fileName": "book.pdf", "sha256": "abc"},
                "qualitySummary": {
                    "pageCount": 1,
                    "pagesWithText": 0,
                    "pagesNeedingReview": [1],
                    "totalNonWhitespaceCharacterCount": 0,
                    "totalReplacementCharacterCount": 0,
                },
            }
        )

        self.assertIn("需人工检查/可能需 OCR 的页：1", report)
        self.assertIn("含替换字符页：无", report)
        self.assertIn("不能仅凭该标记判定需要 OCR", report)

    def test_pdf_with_undecodable_glyphs_requires_review(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            source = Path(temporary_dir) / "missing-unicode.pdf"
            source.write_bytes(missing_unicode_pdf_bytes())
            draft = cli.extract_draft(source)

        page = draft["pages"][0]
        self.assertGreater(page["nonWhitespaceCharacterCount"], 24)
        self.assertEqual(page["cidPlaceholderCount"], 6)
        self.assertEqual(page["extractionStatus"], "cid_placeholders")
        self.assertTrue(page["ocrReviewSuggested"])
        self.assertEqual(draft["qualitySummary"]["pagesNeedingReview"], [1])
        self.assertEqual(draft["qualitySummary"]["pagesWithCidPlaceholders"], [1])
        self.assertEqual(draft["qualitySummary"]["totalCidPlaceholderCount"], 6)
        self.assertIn("含未解码 CID 字形页：1", cli.render_report(draft))

    def test_cid_placeholders_in_layout_text_require_review(self):
        page = MagicMock()
        page.width = 595.0
        page.height = 842.0
        page.extract_text.side_effect = ["正常文本", "(cid:123)"]

        record = cli._page_record(1, page, low_text_threshold=1)

        self.assertEqual(record["cidPlaceholderCount"], 1)
        self.assertEqual(record["extractionStatus"], "cid_placeholders")
        self.assertTrue(record["ocrReviewSuggested"])

    def test_output_writer_refuses_to_replace_existing_file_without_force(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            output = Path(temporary_dir) / "draft.json"
            output.write_text("old", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                cli._write_atomic(output, "new", force=False)
            self.assertEqual(output.read_text(encoding="utf-8"), "old")

    def test_invalid_threshold_fails_before_reading_pdf(self):
        with self.assertRaises(ValueError):
            cli.extract_draft(Path("not-read.pdf"), low_text_threshold=0)


if __name__ == "__main__":
    unittest.main()
