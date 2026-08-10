#!/usr/bin/env python3
"""Download Raveby wallpapers by rewriting their listed resolution URL.

Use this script only for content you are authorized to download and in
accordance with Raveby's terms of service.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, unquote, urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen


BASE_URL = "https://raveby.com"
START_URL = f"{BASE_URL}/wallpapers"
DEFAULT_RESOLUTION = "6688x3764"
STATE_VERSION = 1
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/127.0 Safari/537.36 RavebyWallpaperDownloader/1.0"
)
TRANSIENT_HTTP_CODES = {408, 425, 429, 500, 502, 503, 504}
RESOLUTION_RE = re.compile(r"(?<=-)\d{2,5}x\d{2,5}(?=-)")
VALID_RESOLUTION_RE = re.compile(r"^\d{2,5}x\d{2,5}$")


class LinkCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag.lower() != "a":
            return
        for name, value in attrs:
            if name.lower() == "href" and value:
                self.links.append(value)
                return


class RateLimiter:
    def __init__(self, delay: float) -> None:
        self.delay = delay
        self._lock = threading.Lock()
        self._next_request_at = 0.0

    def wait(self) -> None:
        if self.delay <= 0:
            return
        with self._lock:
            now = time.monotonic()
            wait_seconds = max(0.0, self._next_request_at - now)
            self._next_request_at = max(now, self._next_request_at) + self.delay
        if wait_seconds:
            time.sleep(wait_seconds)


class HttpClient:
    def __init__(self, delay: float, timeout: float, retries: int) -> None:
        self.rate_limiter = RateLimiter(delay)
        self.timeout = timeout
        self.retries = retries

    def get_text(self, url: str) -> str:
        for attempt in range(self.retries + 1):
            try:
                self.rate_limiter.wait()
                request = Request(
                    url,
                    headers={
                        "User-Agent": USER_AGENT,
                        "Accept": "text/html,application/xhtml+xml",
                    },
                )
                with urlopen(request, timeout=self.timeout) as response:
                    content_type = response.headers.get_content_type()
                    if content_type not in {"text/html", "application/xhtml+xml"}:
                        raise RuntimeError(
                            f"expected HTML from {url}, received {content_type}"
                        )
                    charset = response.headers.get_content_charset() or "utf-8"
                    return response.read().decode(charset, errors="replace")
            except (HTTPError, URLError, OSError, RuntimeError) as exc:
                if not self._should_retry(exc, attempt):
                    raise
                self._backoff(attempt, url, exc)
        raise AssertionError("retry loop ended unexpectedly")

    def download(self, url: str, destination: Path) -> int:
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            try:
                return self._download_once(url, destination)
            except (HTTPError, URLError, OSError, RuntimeError) as exc:
                last_error = exc
                if not self._should_retry(exc, attempt):
                    raise
                self._backoff(attempt, url, exc)
        assert last_error is not None
        raise last_error

    def _download_once(self, url: str, destination: Path) -> int:
        partial = destination.with_name(f"{destination.name}.part")
        partial_size = partial.stat().st_size if partial.is_file() else 0
        headers = {
            "User-Agent": USER_AGENT,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        }
        if partial_size:
            headers["Range"] = f"bytes={partial_size}-"

        self.rate_limiter.wait()
        request = Request(url, headers=headers)
        with urlopen(request, timeout=self.timeout) as response:
            content_type = response.headers.get_content_type()
            if not content_type.startswith("image/"):
                raise RuntimeError(
                    f"expected an image from {url}, received {content_type}"
                )

            status = getattr(response, "status", 200)
            append = partial_size > 0 and status == 206
            mode = "ab" if append else "wb"
            with partial.open(mode) as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)

        if not partial.is_file() or partial.stat().st_size == 0:
            raise RuntimeError(f"download produced an empty file: {url}")
        os.replace(partial, destination)
        return destination.stat().st_size

    def _should_retry(self, exc: Exception, attempt: int) -> bool:
        if attempt >= self.retries:
            return False
        if isinstance(exc, HTTPError):
            return exc.code in TRANSIENT_HTTP_CODES
        return True

    @staticmethod
    def _backoff(attempt: int, url: str, exc: Exception) -> None:
        wait_seconds = min(30.0, 2.0**attempt)
        print(
            f"[retry {attempt + 1}] {url}: {exc}; waiting {wait_seconds:.0f}s",
            file=sys.stderr,
            flush=True,
        )
        time.sleep(wait_seconds)


@dataclass(frozen=True)
class DownloadResult:
    detail_url: str
    status: str
    download_url: str | None = None
    filename: str | None = None
    size: int = 0
    error: str | None = None


def collect_links(html: str) -> list[str]:
    parser = LinkCollector()
    parser.feed(html)
    return parser.links


def is_raveby_url(url: str) -> bool:
    return (urlsplit(url).hostname or "").lower() in {"raveby.com", "www.raveby.com"}


def normalize_url(href: str, page_url: str) -> str:
    parsed = urlsplit(urljoin(page_url, href))
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, parsed.query, ""))


def extract_listing(html: str, page_url: str) -> tuple[list[str], str | None]:
    details: list[str] = []
    seen: set[str] = set()
    next_url: str | None = None

    for href in collect_links(html):
        absolute = normalize_url(href, page_url)
        if not is_raveby_url(absolute):
            continue
        parsed = urlsplit(absolute)
        if parsed.path.startswith("/wallpaper/") and not parsed.path.startswith(
            "/wallpaper/download/"
        ):
            if absolute not in seen:
                seen.add(absolute)
                details.append(absolute)
            continue
        if parsed.path.rstrip("/") == "/wallpapers" and "after" in parse_qs(
            parsed.query
        ):
            next_url = absolute

    return details, next_url


def extract_download_url(html: str, detail_url: str, resolution: str) -> str:
    for href in collect_links(html):
        listed_url = normalize_url(href, detail_url)
        parsed = urlsplit(listed_url)
        if not is_raveby_url(listed_url):
            continue
        if not parsed.path.startswith("/wallpaper/download/"):
            continue
        if not RESOLUTION_RE.search(parsed.path):
            continue
        return rewrite_resolution(listed_url, resolution)
    raise RuntimeError("detail page contains no supported wallpaper download link")


def rewrite_resolution(url: str, resolution: str) -> str:
    parsed = urlsplit(url)
    matches = list(RESOLUTION_RE.finditer(parsed.path))
    if not matches:
        raise RuntimeError(f"download URL has no replaceable resolution: {url}")
    match = matches[-1]
    rewritten_path = (
        parsed.path[: match.start()] + resolution + parsed.path[match.end() :]
    )
    return urlunsplit(
        (parsed.scheme, parsed.netloc, rewritten_path, parsed.query, parsed.fragment)
    )


def filename_from_url(url: str) -> str:
    filename = Path(unquote(urlsplit(url).path)).name
    filename = re.sub(r"[^A-Za-z0-9._-]+", "_", filename)
    if not filename or filename in {".", ".."}:
        raise RuntimeError(f"cannot derive a safe filename from {url}")
    return filename


def completed_file_exists(output_dir: Path, record: Any) -> bool:
    if not isinstance(record, dict):
        return False
    filename = record.get("filename")
    if not isinstance(filename, str) or not filename:
        return False
    path = output_dir / filename
    return path.is_file() and path.stat().st_size > 0


def process_detail(
    detail_url: str,
    *,
    client: HttpClient,
    output_dir: Path,
    resolution: str,
    dry_run: bool,
) -> DownloadResult:
    try:
        html = client.get_text(detail_url)
        download_url = extract_download_url(html, detail_url, resolution)
        filename = filename_from_url(download_url)
        destination = output_dir / filename
        if destination.is_file() and destination.stat().st_size > 0:
            return DownloadResult(
                detail_url,
                "exists",
                download_url=download_url,
                filename=filename,
                size=destination.stat().st_size,
            )
        if dry_run:
            return DownloadResult(
                detail_url,
                "dry-run",
                download_url=download_url,
                filename=filename,
            )
        size = client.download(download_url, destination)
        return DownloadResult(
            detail_url,
            "downloaded",
            download_url=download_url,
            filename=filename,
            size=size,
        )
    except Exception as exc:  # Keep one bad wallpaper from stopping the crawl.
        return DownloadResult(detail_url, "failed", error=str(exc))


def process_batch(
    detail_urls: Iterable[str],
    *,
    client: HttpClient,
    output_dir: Path,
    resolution: str,
    workers: int,
    dry_run: bool,
) -> list[DownloadResult]:
    urls = list(detail_urls)
    if not urls:
        return []

    results: list[DownloadResult] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                process_detail,
                detail_url,
                client=client,
                output_dir=output_dir,
                resolution=resolution,
                dry_run=dry_run,
            ): detail_url
            for detail_url in urls
        }
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            if result.status == "failed":
                print(
                    f"[failed] {result.detail_url}: {result.error}",
                    file=sys.stderr,
                    flush=True,
                )
            elif result.status == "dry-run":
                print(f"[dry-run] {result.download_url}", flush=True)
            else:
                size_mb = result.size / (1024 * 1024)
                print(
                    f"[{result.status}] {result.filename} ({size_mb:.2f} MiB)",
                    flush=True,
                )
    return results


def create_state(resolution: str) -> dict[str, Any]:
    return {
        "version": STATE_VERSION,
        "resolution": resolution,
        "next_list_url": START_URL,
        "crawl_complete": False,
        "completed": {},
        "pending": {},
    }


def load_state(path: Path, resolution: str, refresh: bool) -> dict[str, Any]:
    if not path.is_file():
        return create_state(resolution)
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot read state file {path}: {exc}") from exc
    if state.get("version") != STATE_VERSION:
        raise RuntimeError(f"unsupported state file version in {path}")
    if state.get("resolution") != resolution:
        raise RuntimeError(
            f"state file resolution is {state.get('resolution')}, expected {resolution}"
        )
    if not isinstance(state.get("completed"), dict) or not isinstance(
        state.get("pending"), dict
    ):
        raise RuntimeError(f"invalid state file structure in {path}")
    if refresh:
        state["next_list_url"] = START_URL
        state["crawl_complete"] = False
    return state


def save_state(path: Path, state: dict[str, Any]) -> None:
    state["updated_at"] = datetime.now(timezone.utc).isoformat()
    temporary = path.with_name(f"{path.name}.tmp")
    temporary.write_text(
        json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def apply_results(state: dict[str, Any], results: Iterable[DownloadResult]) -> None:
    completed: dict[str, Any] = state["completed"]
    pending: dict[str, Any] = state["pending"]
    for result in results:
        if result.status in {"downloaded", "exists"}:
            completed[result.detail_url] = {
                "download_url": result.download_url,
                "filename": result.filename,
                "size": result.size,
            }
            pending.pop(result.detail_url, None)
        elif result.status == "failed":
            pending[result.detail_url] = result.error


def pending_urls(state: dict[str, Any], output_dir: Path) -> list[str]:
    completed: dict[str, Any] = state["completed"]
    return [
        detail_url
        for detail_url in state["pending"]
        if not completed_file_exists(output_dir, completed.get(detail_url))
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Crawl Raveby's public wallpaper listing and download each wallpaper "
            "after replacing the listed resolution in its download URL."
        ),
        epilog=(
            "The site currently contains thousands of wallpapers, so a full run may "
            "need substantial time and disk space. Interrupted runs resume from a "
            "state file in the output directory."
        ),
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("raveby-wallpapers"),
        help="download directory (default: %(default)s)",
    )
    parser.add_argument(
        "--resolution",
        default=DEFAULT_RESOLUTION,
        help="replacement resolution in WIDTHxHEIGHT form (default: %(default)s)",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=3,
        help="parallel detail/download workers (default: %(default)s)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="minimum delay between all HTTP requests, in seconds (default: %(default)s)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=60.0,
        help="per-request timeout in seconds (default: %(default)s)",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=3,
        help="retry count for transient failures (default: %(default)s)",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="crawl from the first listing page again while keeping completed files",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print rewritten download URLs without downloading or changing state",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=0,
        help="stop after this many complete listing pages; 0 means unlimited",
    )
    parser.add_argument(
        "--max-items",
        type=int,
        default=0,
        help="process at most this many pending/new wallpapers; 0 means unlimited",
    )
    args = parser.parse_args()

    if not VALID_RESOLUTION_RE.fullmatch(args.resolution):
        parser.error("--resolution must use WIDTHxHEIGHT, for example 6688x3764")
    if args.workers < 1:
        parser.error("--workers must be at least 1")
    if args.delay < 0 or args.timeout <= 0 or args.retries < 0:
        parser.error("--delay, --timeout, and --retries must not be negative")
    if args.max_pages < 0 or args.max_items < 0:
        parser.error("--max-pages and --max-items must not be negative")
    return args


def run(args: argparse.Namespace) -> int:
    output_dir = args.output.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    state_path = output_dir / f".raveby-state-{args.resolution}.json"
    state = (
        create_state(args.resolution)
        if args.dry_run
        else load_state(state_path, args.resolution, args.refresh)
    )
    client = HttpClient(args.delay, args.timeout, args.retries)
    attempted = 0
    pages = 0
    inspected_pages = 0
    stopped_by_limit = False

    def remaining_budget() -> int | None:
        if args.max_items == 0:
            return None
        return max(0, args.max_items - attempted)

    try:
        retry_urls = pending_urls(state, output_dir)
        if retry_urls:
            budget = remaining_budget()
            selected = retry_urls if budget is None else retry_urls[:budget]
            if selected:
                print(f"Retrying {len(selected)} pending wallpaper(s)...", flush=True)
                results = process_batch(
                    selected,
                    client=client,
                    output_dir=output_dir,
                    resolution=args.resolution,
                    workers=args.workers,
                    dry_run=args.dry_run,
                )
                attempted += len(selected)
                if not args.dry_run:
                    apply_results(state, results)
                    save_state(state_path, state)
            if len(selected) < len(retry_urls):
                stopped_by_limit = True

        current_url = state.get("next_list_url")
        visited_pages: set[str] = set()
        while current_url and not stopped_by_limit:
            if args.max_pages and pages >= args.max_pages:
                stopped_by_limit = True
                break
            budget = remaining_budget()
            if budget == 0:
                stopped_by_limit = True
                break
            if current_url in visited_pages:
                raise RuntimeError(f"pagination loop detected at {current_url}")
            visited_pages.add(current_url)

            print(f"[listing {pages + 1}] {current_url}", flush=True)
            html = client.get_text(current_url)
            details, next_url = extract_listing(html, current_url)
            if not details:
                raise RuntimeError(f"listing page contains no wallpaper links: {current_url}")
            inspected_pages += 1

            completed: dict[str, Any] = state["completed"]
            candidates = [
                detail_url
                for detail_url in details
                if not completed_file_exists(output_dir, completed.get(detail_url))
            ]
            selected = candidates if budget is None else candidates[:budget]
            page_truncated = len(selected) < len(candidates)

            results = process_batch(
                selected,
                client=client,
                output_dir=output_dir,
                resolution=args.resolution,
                workers=args.workers,
                dry_run=args.dry_run,
            )
            attempted += len(selected)
            if not args.dry_run:
                apply_results(state, results)

            if page_truncated:
                stopped_by_limit = True
                if not args.dry_run:
                    state["next_list_url"] = current_url
                    save_state(state_path, state)
                break

            pages += 1
            current_url = next_url
            state["next_list_url"] = current_url
            state["crawl_complete"] = current_url is None
            if not args.dry_run:
                save_state(state_path, state)

        if not args.dry_run and not stopped_by_limit:
            state["next_list_url"] = current_url
            state["crawl_complete"] = current_url is None
            save_state(state_path, state)
    except KeyboardInterrupt:
        print("\nInterrupted; completed files are safe and the current page will be retried.")
        if not args.dry_run:
            save_state(state_path, state)
        return 130

    completed_count = len(state["completed"])
    pending_count = len(state["pending"])
    if args.dry_run:
        print(
            f"Dry run complete: inspected {attempted} wallpaper(s) "
            f"on {inspected_pages} listing page(s)."
        )
        return 0
    if stopped_by_limit:
        print(
            f"Stopped at the requested limit. Completed: {completed_count}; "
            f"pending failures: {pending_count}. Resume with the same command."
        )
        return 0
    print(
        f"Crawl complete. Downloaded/existing: {completed_count}; "
        f"pending failures: {pending_count}."
    )
    return 1 if pending_count else 0


def main() -> int:
    try:
        return run(parse_args())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
