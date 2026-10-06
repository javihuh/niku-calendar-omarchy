#!/usr/bin/env python3
"""Optional, read-only Canvas source for Niku Calendar."""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CONFIG_FILE = CONFIG_HOME / "niku" / "canvas.json"
CACHE_FILE = CACHE_HOME / "niku" / "canvas.json"
REFRESH_SECONDS = 15 * 60
MAX_PAGES = 20


def canvas_origin(value: str) -> str:
    base = value.strip().rstrip("/")
    if base and "://" not in base:
        base = "https://" + base
    parsed = urlsplit(base)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or parsed.path or parsed.port not in (None, 443)
            or any(char.isspace() for char in base)):
        raise ValueError("invalid_url")
    return base


def public_settings(path: Path = CONFIG_FILE) -> dict:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        base = canvas_origin(str(config.get("baseUrl", "")))
        token_file = Path(str(config.get("tokenFile", ""))).expanduser()
        has_token = bool(config.get("tokenFile") and token_file.is_file()
                         and not token_file.stat().st_mode & 0o077)
        return {"baseUrl": base, "hasToken": has_token}
    except (OSError, ValueError, TypeError, AttributeError):
        return {"baseUrl": "", "hasToken": False}


def save_private(path: Path, value: str) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".canvas-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(value)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def configure(payload: dict, path: Path = CONFIG_FILE) -> dict:
    try:
        base = canvas_origin(str(payload.get("baseUrl", "")))
        token = str(payload.get("token", "")).strip()
        if len(token) > 4096 or any(char.isspace() for char in token):
            return {"ok": False, "error": "invalid_token"}
        if token:
            token_path = path.parent / "canvas-token"
            save_private(token_path, token + "\n")
        else:
            source = configured_source(path)
            if source is None:
                return {"ok": False, "error": "missing_token"}
            config = json.loads(path.read_text(encoding="utf-8"))
            token_path = Path(str(config["tokenFile"])).expanduser()
        save_private(path, json.dumps({"baseUrl": base, "tokenFile": str(token_path)}) + "\n")
        return {"ok": True, "baseUrl": base}
    except (ValueError, TypeError, AttributeError, KeyError) as error:
        code = str(error)
        return {"ok": False, "error": code if code in ("invalid_url", "missing_token") else "invalid_token"}
    except OSError:
        return {"ok": False, "error": "save_failed"}


def configured_source(path: Path = CONFIG_FILE) -> tuple[str, str] | None:
    if not path.exists():
        return None
    config = json.loads(path.read_text(encoding="utf-8"))
    base = canvas_origin(str(config.get("baseUrl", "")))
    token_path = Path(str(config.get("tokenFile", ""))).expanduser()
    if not config.get("tokenFile") or not token_path.is_file():
        raise ValueError("Canvas tokenFile does not exist")
    if token_path.stat().st_mode & 0o077:
        raise ValueError("Canvas tokenFile must be private (chmod 600)")
    token = token_path.read_text(encoding="utf-8").strip()
    if not token or "\n" in token or "\r" in token:
        raise ValueError("Canvas tokenFile is empty or invalid")
    return base, token


def read_cache(path: Path = CACHE_FILE) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if data.get("version") == 1 else {}
    except (OSError, ValueError, AttributeError):
        return {}


def save_cache(data: dict, path: Path = CACHE_FILE) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".canvas-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def pages(base: str, token: str, resource: str, params: dict, opener=urlopen) -> list:
    url = base + resource + "?" + urlencode(params)
    results = []
    visited = set()
    for _ in range(MAX_PAGES):
        if url in visited or not url.startswith(base + "/api/v1/"):
            raise ValueError("Invalid Canvas pagination link")
        visited.add(url)
        with opener(Request(url, headers={"Authorization": "Bearer " + token,
                                          "Accept": "application/json",
                                          "User-Agent": "Niku Calendar/0.5"}), timeout=12) as response:
            items = json.load(response)
            if not isinstance(items, list):
                raise ValueError("Unexpected Canvas response")
            results.extend(items)
            links = response.headers.get("Link", "")
        next_url = ""
        for part in links.split(","):
            match = re.search(r'<([^>]+)>;\s*rel="next"', part)
            if match:
                next_url = match.group(1)
                break
        if not next_url:
            return results
        target = urlsplit(next_url)
        origin = urlsplit(base)
        if target.scheme != "https" or target.netloc != origin.netloc or not target.path.startswith("/api/v1/"):
            raise ValueError("Invalid Canvas pagination origin")
        url = next_url
    raise ValueError("Canvas pagination limit exceeded")


def normalize(courses: list, planner: list, base: str) -> dict:
    names = {str(course["id"]): str(course.get("name") or course.get("course_code") or "Canvas")
             for course in courses if isinstance(course, dict) and "id" in course}
    assignments = []
    seen = set()
    for entry in planner:
        if not isinstance(entry, dict) or str(entry.get("plannable_type", "")).lower() != "assignment":
            continue
        item = entry.get("plannable") or {}
        if not isinstance(item, dict):
            continue
        course_id = str(entry.get("course_id") or item.get("course_id") or "")
        ident = str(entry.get("plannable_id") or item.get("id") or "")
        due = item.get("due_at") or item.get("todo_date")
        if not ident or not due or (course_id, ident) in seen:
            continue
        seen.add((course_id, ident))
        override = entry.get("planner_override") or {}
        submission = entry.get("submissions") or {}
        done = bool(override.get("marked_complete") or override.get("dismissed")
                    or (isinstance(submission, dict) and (submission.get("graded")
                        or submission.get("submitted_at") or submission.get("workflow_state") in ("submitted", "graded"))))
        raw_url = str(entry.get("html_url") or item.get("html_url") or "")
        link = base + raw_url if raw_url.startswith("/") else raw_url
        if not link.startswith(base + "/"):
            link = ""
        assignments.append({"id": course_id + ":" + ident, "course": names.get(course_id, "Canvas"),
                            "title": str(item.get("title") or item.get("name") or "Tarea"),
                            "dueAt": str(due), "done": done, "url": link})
    assignments.sort(key=lambda item: item["dueAt"])
    return {"courses": names, "assignments": assignments}


def status(config_path: Path = CONFIG_FILE, cache_path: Path = CACHE_FILE,
           now: float | None = None, opener=urlopen, force: bool = False) -> dict:
    try:
        source = configured_source(config_path)
    except (OSError, ValueError, TypeError) as error:
        return {"ok": False, "configured": False, "error": str(error), "assignments": [], "courses": {}}
    if source is None:
        return {"ok": True, "configured": False, "assignments": [], "courses": {}}
    base, token = source
    current = time.time() if now is None else now
    cache = read_cache(cache_path)
    if cache.get("baseUrl") != base:
        cache = {}
    cached = cache.get("data") if isinstance(cache.get("data"), dict) else None
    if cached and not force and current - cache.get("fetchedAt", 0) < REFRESH_SECONDS:
        return {"ok": True, "configured": True, "stale": False, "updatedAt": cache["fetchedAt"], **cached}
    try:
        courses = pages(base, token, "/api/v1/courses", {"enrollment_state": "active", "per_page": 100}, opener)
        start = (datetime.now().date() - timedelta(days=7)).isoformat()
        end = (datetime.now().date() + timedelta(days=45)).isoformat()
        planner = pages(base, token, "/api/v1/planner/items",
                        {"start_date": start, "end_date": end, "per_page": 100}, opener)
        data = normalize(courses, planner, base)
        save_cache({"version": 1, "baseUrl": base, "fetchedAt": current, "data": data}, cache_path)
        return {"ok": True, "configured": True, "stale": False, "updatedAt": current, **data}
    except (OSError, URLError, HTTPError, ValueError, TypeError):
        if cached:
            return {"ok": True, "configured": True, "stale": True, "updatedAt": cache.get("fetchedAt"), **cached}
        return {"ok": False, "configured": True, "stale": True, "error": "Canvas unavailable", "assignments": [], "courses": {}}


if __name__ == "__main__":
    if "--settings" in sys.argv:
        result = public_settings()
    elif "--configure" in sys.argv:
        try:
            result = configure(json.loads(sys.stdin.readline(16385)))
        except (ValueError, TypeError, AttributeError):
            result = {"ok": False, "error": "invalid_input"}
    else:
        result = status(force="--refresh" in sys.argv)
    print(json.dumps(result, ensure_ascii=False))
