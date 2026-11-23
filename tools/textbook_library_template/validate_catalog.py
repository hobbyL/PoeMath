#!/usr/bin/env python3
"""Prepare and validate a public PoeMath textbook catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import quote, urlsplit

import jsonschema
import pypdfium2 as pdfium
from PIL import Image


def find_library_root() -> Path:
    script_dir = Path(__file__).resolve().parent
    for candidate in (script_dir, *script_dir.parents):
        if (candidate / "catalog.json").is_file() and (
            candidate / "catalog.schema.json"
        ).is_file():
            return candidate
    raise RuntimeError("找不到 catalog.json 与 catalog.schema.json")


ROOT = find_library_root()
CATALOG_PATH = ROOT / "catalog.json"
SCHEMA_PATH = ROOT / "catalog.schema.json"
MAX_WARNING_BYTES = 50 * 1024 * 1024
MAX_FILE_BYTES = 100 * 1024 * 1024
MAX_COVER_BYTES = 2 * 1024 * 1024
MAX_COVER_SIDE = 1024


class CatalogError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_file(root: Path, raw_path: str) -> tuple[Path, str]:
    if not raw_path or "\\" in raw_path or "\x00" in raw_path:
        raise CatalogError(f"路径无效：{raw_path!r}")
    relative = PurePosixPath(raw_path)
    if relative.is_absolute() or any(part in ("", ".", "..") for part in relative.parts):
        raise CatalogError(f"路径必须是仓库内的相对路径：{raw_path}")
    candidate = root.joinpath(*relative.parts)
    try:
        candidate.resolve(strict=True).relative_to(root.resolve())
    except (OSError, ValueError) as error:
        raise CatalogError(f"路径不存在或越界：{raw_path}") from error
    if not candidate.is_file():
        raise CatalogError(f"路径不是文件：{raw_path}")
    return candidate, relative.as_posix()


def git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CatalogError(f"git {' '.join(args)} 失败：{detail}")
    return result.stdout.strip()


def file_commit(root: Path, relative: str) -> str:
    commit = git(root, "log", "-1", "--format=%H", "--", relative)
    if len(commit) != 40:
        raise CatalogError(f"文件尚未提交到 Git：{relative}")
    return commit


def tree_blob(root: Path, commit: str, relative: str) -> str:
    blob = git(root, "rev-parse", f"{commit}:{relative}")
    if len(blob) != 40 or git(root, "cat-file", "-t", blob) != "blob":
        raise CatalogError(f"Git commit 中找不到文件 blob：{relative}")
    return blob


def worktree_blob(root: Path, relative: str) -> str:
    return git(root, "hash-object", relative)


def pdf_info(path: Path) -> tuple[str, int, int]:
    try:
        with pdfium.PdfDocument(str(path)) as document:
            page_count = len(document)
    except Exception as error:
        raise CatalogError(f"PDFium 无法打开 {path.name}：{error}") from error
    if page_count < 1:
        raise CatalogError(f"PDF 没有页面：{path.name}")
    return sha256_file(path), path.stat().st_size, page_count


def render_cover(pdf_path: Path, cover_path: Path) -> None:
    try:
        with pdfium.PdfDocument(str(pdf_path)) as document:
            if len(document) < 1:
                raise CatalogError(f"PDF 没有页面：{pdf_path.name}")
            page = document[0]
            try:
                width, height = page.get_size()
                if width <= 0 or height <= 0:
                    raise CatalogError(f"PDF 首页尺寸无效：{pdf_path.name}")
                scale = min(1.0, 768 / max(width, height))
                image = page.render(
                    scale=scale,
                    fill_color=(255, 255, 255, 255),
                ).to_pil()
            finally:
                page.close()
        cover_path.parent.mkdir(parents=True, exist_ok=True)
        image.convert("RGB").save(cover_path, format="WEBP", quality=84, method=6)
    except CatalogError:
        raise
    except Exception as error:
        raise CatalogError(f"无法生成封面 {cover_path.name}：{error}") from error


def load_catalog(root: Path = ROOT) -> dict:
    path = root / "catalog.json"
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CatalogError(f"无法读取 {path}: {error}") from error


def write_catalog(root: Path, catalog: dict) -> None:
    path = root / "catalog.json"
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def canonical_pdf_url(repository: str, commit: str, path: str) -> str:
    encoded = quote(f"{repository}/{commit}/{path}", safe="/")
    return f"https://raw.githubusercontent.com/{encoded}"


def expected_book_path(book: dict) -> str:
    semester = {"上": "upper", "下": "lower"}.get(book["semester"])
    if semester is None:
        raise CatalogError(f"学期无效：{book['editionId']}")
    return (
        f"books/{book['subject']}/grade-{book['grade']:02d}/"
        f"{semester}/{book['editionId']}.pdf"
    )


def pin_catalog(root: Path = ROOT) -> None:
    catalog = load_catalog(root)
    repository = catalog.get("repository")
    if not isinstance(repository, str) or "/" not in repository:
        raise CatalogError("catalog.repository 必须是 owner/repository")
    updated = json.loads(json.dumps(catalog))
    for book in updated.get("books", []):
        source_path = book.get("sourcePath")
        cover_path = book.get("coverPath")
        if not isinstance(source_path, str) or not isinstance(cover_path, str):
            raise CatalogError("每条记录必须先填写 sourcePath 和 coverPath")
        pdf, source_path = safe_file(root, source_path)
        cover, cover_path = safe_file(root, cover_path)
        if source_path != expected_book_path(book):
            raise CatalogError(f"sourcePath 与学科/年级/学期/版次不匹配：{source_path}")
        pdf_sha, file_size, page_count = pdf_info(pdf)
        if file_size >= MAX_FILE_BYTES:
            raise CatalogError(f"PDF 达到或超过 100 MiB，常规 Git 不支持：{source_path}")
        cover_sha = sha256_file(cover)
        if cover_path != f"covers/{pdf_sha}.webp":
            raise CatalogError(f"coverPath 必须使用 PDF SHA 命名：covers/{pdf_sha}.webp")
        pdf_commit = file_commit(root, source_path)
        cover_commit = file_commit(root, cover_path)
        if pdf_commit != cover_commit:
            raise CatalogError(f"PDF 与封面必须在同一个 Git commit：{source_path}")
        pdf_blob = tree_blob(root, pdf_commit, source_path)
        cover_blob = tree_blob(root, pdf_commit, cover_path)
        if worktree_blob(root, source_path) != pdf_blob:
            raise CatalogError(f"PDF 工作区内容与已提交 commit 不同：{source_path}")
        if worktree_blob(root, cover_path) != cover_blob:
            raise CatalogError(f"封面工作区内容与已提交 commit 不同：{cover_path}")
        book.update(
            {
                "sha256": pdf_sha,
                "bytes": file_size,
                "pageCount": page_count,
                "downloadUrl": canonical_pdf_url(repository, pdf_commit, source_path),
                "sourceRepository": repository,
                "sourceCommit": pdf_commit,
                "sourcePath": source_path,
                "gitBlobSha": pdf_blob,
                "checkedAt": datetime.now(timezone.utc).isoformat(),
                "evidencePdfPages": sorted(set(book.get("evidencePdfPages", [1]))),
                "coverPath": cover_path,
                "coverSha256": cover_sha,
                "coverSourcePdfPage": 1,
            }
        )
    write_catalog(root, updated)


def validate_catalog(root: Path = ROOT) -> list[str]:
    catalog = load_catalog(root)
    schema = json.loads((root / "catalog.schema.json").read_text(encoding="utf-8"))
    try:
        jsonschema.validate(
            catalog,
            schema,
            format_checker=jsonschema.FormatChecker(),
        )
    except jsonschema.ValidationError as error:
        raise CatalogError(f"catalog.json schema 错误：{error.message}") from error
    except jsonschema.SchemaError as error:
        raise CatalogError(f"catalog.schema.json 无效：{error.message}") from error

    warnings: list[str] = []
    seen_sha: set[str] = set()
    seen_ids: set[tuple[str, str]] = set()
    repository = catalog["repository"]
    for book in catalog["books"]:
        book_id = book["editionId"]
        identity = (book["subject"], book_id)
        if identity in seen_ids:
            raise CatalogError(f"版次 ID 重复：{book_id}")
        seen_ids.add(identity)
        if book["sha256"] in seen_sha:
            raise CatalogError(f"PDF SHA-256 重复：{book['sha256']}")
        seen_sha.add(book["sha256"])
        if book["sourceRepository"] != repository:
            raise CatalogError(f"来源仓库与 catalog.repository 不一致：{book_id}")
        if book["sourcePath"] != expected_book_path(book):
            raise CatalogError(f"sourcePath 与册次信息不匹配：{book_id}")
        if book["coverPath"] != f"covers/{book['sha256']}.webp":
            raise CatalogError(f"coverPath 与 PDF SHA 不匹配：{book_id}")
        if (
            not book["redistributionPermissionVerified"]
            or not book["redistributionEvidence"].strip()
        ):
            raise CatalogError(f"公开书目缺少再分发核验记录：{book_id}")

        pdf, source_path = safe_file(root, book["sourcePath"])
        cover, cover_path = safe_file(root, book["coverPath"])
        file_size = pdf.stat().st_size
        if file_size >= MAX_FILE_BYTES:
            raise CatalogError(f"PDF 达到或超过 100 MiB，常规 Git 不支持：{source_path}")
        if file_size > MAX_WARNING_BYTES:
            warnings.append(f"{source_path} 超过 50 MiB，GitHub 会显示大文件警告")
        pdf_sha, actual_bytes, page_count = pdf_info(pdf)
        if actual_bytes != book["bytes"]:
            raise CatalogError(f"PDF 字节数不匹配：{source_path}")
        if pdf_sha != book["sha256"]:
            raise CatalogError(f"PDF SHA-256 不匹配：{source_path}")
        if page_count != book["pageCount"]:
            raise CatalogError(f"PDF 页数不匹配：{source_path}")
        if any(page > page_count for page in book["evidencePdfPages"]):
            raise CatalogError(f"版次证据页超出 PDF 页数：{source_path}")
        if cover.stat().st_size > MAX_COVER_BYTES:
            raise CatalogError(f"封面超过 2 MiB：{cover_path}")
        if sha256_file(cover) != book["coverSha256"]:
            raise CatalogError(f"封面 SHA-256 不匹配：{cover_path}")
        try:
            with Image.open(cover) as image:
                if image.format != "WEBP" or max(image.size) > MAX_COVER_SIDE:
                    raise CatalogError(f"封面必须是最长边不超过 1024px 的 WebP：{cover_path}")
                image.verify()
        except CatalogError:
            raise
        except Exception as error:
            raise CatalogError(f"封面无法解码：{cover_path}: {error}") from error

        commit = book["sourceCommit"]
        blob = tree_blob(root, commit, source_path)
        if blob != book["gitBlobSha"] or worktree_blob(root, source_path) != blob:
            raise CatalogError(f"Git blob SHA 不匹配：{source_path}")
        cover_blob = tree_blob(root, commit, cover_path)
        if worktree_blob(root, cover_path) != cover_blob:
            raise CatalogError(f"封面不在 sourceCommit 中：{cover_path}")
        if book["downloadUrl"] != canonical_pdf_url(repository, commit, source_path):
            raise CatalogError(f"downloadUrl 不是同仓库固定 commit/path：{book_id}")
        parsed = urlsplit(book["downloadUrl"])
        if parsed.scheme != "https" or parsed.hostname != "raw.githubusercontent.com":
            raise CatalogError(f"downloadUrl 必须使用 HTTPS GitHub Raw：{book_id}")
    return warnings


def prepare_pdf(root: Path, raw_pdf: str) -> dict:
    pdf, relative = safe_file(root, raw_pdf)
    if not relative.startswith("books/") or not relative.endswith(".pdf"):
        raise CatalogError("PDF 必须位于 books/ 目录且使用 .pdf 扩展名")
    pdf_sha, file_size, page_count = pdf_info(pdf)
    if file_size >= MAX_FILE_BYTES:
        raise CatalogError(f"PDF 达到或超过 100 MiB，常规 Git 不支持：{relative}")
    cover_path = root / "covers" / f"{pdf_sha}.webp"
    render_cover(pdf, cover_path)
    result = {
        "sha256": pdf_sha,
        "bytes": file_size,
        "pageCount": page_count,
        "evidencePdfPages": [1],
        "coverPath": cover_path.relative_to(root).as_posix(),
        "coverSha256": sha256_file(cover_path),
        "coverSourcePdfPage": 1,
    }
    if file_size > MAX_WARNING_BYTES:
        print("警告：该文件超过 50 MiB，GitHub 会显示大文件警告。", file=sys.stderr)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="教材书库 PDF 准备与目录校验")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="校验目录、Git 来源与所有文件")
    check.set_defaults(command="check")
    prepare = commands.add_parser("prepare", help="检查 PDF 并生成首页 WebP 封面")
    prepare.add_argument("--pdf", required=True, help="相对书库根目录的 PDF 路径")
    pin = commands.add_parser("pin", help="将目录记录绑定到已提交的 PDF/封面 commit")
    pin.set_defaults(command="pin")
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            print(json.dumps(prepare_pdf(ROOT, args.pdf), ensure_ascii=False, indent=2))
        elif args.command == "pin":
            pin_catalog(ROOT)
            print("已更新 catalog.json 的 commit、blob、SHA、大小和页数。")
        else:
            warnings = validate_catalog(ROOT)
            for warning in warnings:
                print(f"警告：{warning}")
            print(f"教材目录校验通过：{len(load_catalog(ROOT)['books'])} 条")
        return 0
    except (CatalogError, OSError, ValueError) as error:
        print(f"教材目录校验失败：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
