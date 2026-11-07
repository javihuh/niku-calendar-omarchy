#!/usr/bin/env python3
"""Optional, read-only Canvas source for Niku Calendar."""

from __future__ import annotations

import json
import argparse
import hashlib
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, HTTPRedirectHandler, build_opener

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CONFIG_FILE = CONFIG_HOME / "niku" / "canvas.json"
CACHE_FILE = CACHE_HOME / "niku" / "canvas.json"
REFRESH_SECONDS = 15 * 60
MAX_PAGES = 20


class CanvasRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        origin, target = urlsplit(req.full_url), urlsplit(newurl)
        if (target.scheme != "https" or target.netloc != origin.netloc
                or not target.path.startswith("/api/v1/")):
            raise ValueError("Invalid Canvas redirect origin")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def canvas_open(request, timeout):
    return build_opener(CanvasRedirectHandler()).open(request, timeout=timeout)


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


def pages(base: str, token: str, resource: str, params: dict, opener=canvas_open) -> list:
    url = base + resource + "?" + urlencode(params, doseq=True)
    results = []
    visited = set()
    for _ in range(MAX_PAGES):
        if url in visited or not url.startswith(base + "/api/v1/"):
            raise ValueError("Invalid Canvas pagination link")
        visited.add(url)
        with opener(Request(url, headers={"Authorization": "Bearer " + token,
                                          "Accept": "application/json",
                                          "User-Agent": "Niku Calendar/0.5"}), timeout=12) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
            if len(raw) > 4 * 1024 * 1024:
                raise ValueError("Canvas response too large")
            items = json.loads(raw)
            if not isinstance(items, list):
                raise ValueError("Unexpected Canvas response")
            results.extend(item for item in items if isinstance(item, dict))
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


def is_submitted(submission):
    if not isinstance(submission, dict) or submission.get("missing"):
        return False
    if isinstance(submission.get("submitted"), bool):
        return submission["submitted"]
    return bool(submission.get("submitted_at") or submission.get("workflow_state") in ("submitted", "graded")
                or submission.get("graded"))


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
        submitted = is_submitted(submission)
        excused = isinstance(submission, dict) and bool(submission.get("excused"))
        done = bool(override.get("marked_complete") or override.get("dismissed") or submitted or excused)
        raw_url = str(entry.get("html_url") or item.get("html_url") or "")
        link = base + raw_url if raw_url.startswith("/") else raw_url
        if not link.startswith(base + "/"):
            link = ""
        assignments.append({"id": course_id + ":" + ident, "courseId": course_id,
                            "submitted": submitted, "excused": excused,
                            "markedComplete": bool(override.get("marked_complete")),
                            "course": names.get(course_id, "Canvas"),
                            "title": str(item.get("title") or item.get("name") or "Tarea"),
                            "dueAt": str(due), "done": done, "url": link})
    assignments.sort(key=lambda item: item["dueAt"])
    return {"courses": names, "assignments": assignments}


def status(config_path: Path = CONFIG_FILE, cache_path: Path = CACHE_FILE,
            now: float | None = None, opener=canvas_open, force: bool = False) -> dict:
    try:
        source = configured_source(config_path)
    except (OSError, ValueError, TypeError) as error:
        return {"ok": False, "configured": False, "error": str(error), "assignments": [], "courses": {}}
    if source is None:
        return {"ok": True, "configured": False, "assignments": [], "courses": {}}
    base, token = source
    current = time.time() if now is None else now
    cache = read_cache(cache_path)
    source_key = hashlib.sha256((base + "\0" + token).encode()).hexdigest()
    if cache.get("baseUrl") != base or cache.get("sourceKey") != source_key:
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
        save_cache({"version": 1, "baseUrl": base, "sourceKey": source_key, "fetchedAt": current, "data": data}, cache_path)
        return {"ok": True, "configured": True, "stale": False, "updatedAt": current, **data}
    except (OSError, URLError, HTTPError, ValueError, TypeError):
        if cached:
            return {"ok": True, "configured": True, "stale": True, "updatedAt": cache.get("fetchedAt"), **cached}
        return {"ok": False, "configured": True, "stale": True, "error": "Canvas unavailable", "assignments": [], "courses": {}}


class PlainHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.hidden += 1
        if tag in ("p", "br", "div", "li"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def plain(value, limit=20000):
    parser = PlainHTML()
    parser.feed(str(value or "")[:100000])
    return "".join(parser.parts).strip()[:limit]


def safe_link(value, base):
    value = str(value or "")[:4096]
    if value.startswith("/") and not value.startswith("//"):
        value = base + value
    parsed = urlsplit(value)
    return value if parsed.scheme in ("https", "http") and parsed.hostname and not parsed.username else ""


def academic(section, course="", force=False, cached_only=False,
             config_path=CONFIG_FILE, cache_dir=None, now=None, opener=canvas_open):
    """Lazy, independently cached academic resources. Never writes to Canvas."""
    empty = {"items": [], "ok": False, "configured": False, "section": section, "courseId": course}
    if section not in ("courses", "assignments", "announcements", "grades", "materials", "calendar"):
        return {**empty, "error": "invalid_section"}
    if course and not re.fullmatch(r"[0-9]{1,20}", course):
        return {**empty, "error": "invalid_course"}
    try:
        source = configured_source(config_path)
        if source is None:
            return empty
        base, token = source
    except (OSError, ValueError, TypeError, AttributeError):
        return {**empty, "error": "configuration"}
    empty["configured"] = True
    scope = hashlib.sha256((base + "\0" + token).encode()).hexdigest()[:24]
    path = (cache_dir or CACHE_FILE.parent / "academic") / scope / (section + "-" + (course or "all") + ".json")
    current = time.time() if now is None else now
    cache = read_cache(path)
    data = cache.get("data")
    fresh = bool(data is not None and current - cache.get("fetchedAt", 0) < REFRESH_SECONDS)
    if cached_only or (fresh and not force):
        return {**empty, **(data or {}), "ok": data is not None, "stale": not fresh,
                "updatedAt": cache.get("fetchedAt", 0)}

    def get(resource, **params):
        return pages(base, token, "/api/v1/" + resource, {"per_page": 100, **params}, opener)

    def row(item, **fields):
        return {"id": str(item.get("id", ""))[:100],
                "title": str(item.get("name") or item.get("title") or "Canvas")[:500],
                "url": safe_link(item.get("html_url"), base), **fields}

    def assignments_for(ident, name=""):
        result = []
        for a in get("courses/" + ident + "/assignments", **{"include[]": "submission"}):
            sub = a.get("submission") or {}
            submitted = is_submitted(sub)
            result.append(row(a, id=ident + ":" + str(a.get("id", "")), courseId=ident, course=name,
                              dueAt=a.get("due_at"), submitted=submitted, markedComplete=False,
                              done=submitted, missing=bool(sub.get("missing")), excused=bool(sub.get("excused")),
                              grade=sub.get("grade"), score=sub.get("score"), points=a.get("points_possible")))
        return result

    try:
        items = []
        partial = False
        if section == "courses":
            items = [row(c, subtitle=str(c.get("course_code") or "")[:500],
                         url=base + "/courses/" + str(c["id"]))
                     for c in get("courses", enrollment_state="active") if str(c.get("id", "")).isdigit()]
        elif section in ("grades", "materials") and not course:
            return {**empty, "ok": True, "chooseCourse": True}
        elif section == "assignments" and not course:
            courses = get("courses", enrollment_state="active")
            selected = [c for c in courses if str(c.get("id", "")).isdigit()][:100]
            partial = len(courses) > 100
            with ThreadPoolExecutor(max_workers=4) as pool:
                jobs = [pool.submit(assignments_for, str(c["id"]), str(c.get("name") or "Canvas")[:500]) for c in selected]
                successes = 0
                for job in jobs:
                    try:
                        items.extend(job.result())
                        successes += 1
                    except (OSError, ValueError, TypeError):
                        partial = True
                if jobs and not successes:
                    raise ValueError("Assignments unavailable")
        elif section in ("assignments", "grades"):
            items = assignments_for(course)
            if section == "grades":
                try:
                    for enrollment in get("courses/" + course + "/enrollments", user_id="self", **{"type[]": "StudentEnrollment"}):
                        grades = enrollment.get("grades") or {}
                        items.insert(0, {"id": "average", "title": "", "average": True,
                                         "grade": grades.get("current_grade"), "score": grades.get("current_score"),
                                         "points": 100, "url": safe_link(grades.get("html_url"), base)})
                except (OSError, ValueError, TypeError):
                    partial = True
        elif section == "announcements":
            ids = [course] if course else [str(c["id"]) for c in get("courses", enrollment_state="active")
                                          if str(c.get("id", "")).isdigit()]
            # Fetch each course independently: one inaccessible course must not hide the others.
            with ThreadPoolExecutor(max_workers=4) as pool:
                jobs = [(ident, pool.submit(get, "announcements", **{"context_codes[]": "course_" + ident,
                         "start_date": (datetime.now().date() - timedelta(days=30)).isoformat()})) for ident in ids[:100]]
                successes = 0
                for ident, job in jobs:
                    try:
                        for a in job.result():
                            items.append(row(a, body=plain(a.get("message")), date=a.get("posted_at") or "", courseId=ident))
                        successes += 1
                    except (OSError, ValueError, TypeError):
                        partial = True
                if jobs and not successes:
                    raise ValueError("Announcements unavailable")
            items.sort(key=lambda a: a.get("date", ""), reverse=True)
        elif section == "materials":
            modules = get("courses/" + course + "/modules", **{"include[]": "items"})
            partial = len(modules) > 100
            for module in modules[:100]:
                children = module.get("items")
                if children is None or len(children) < int(module.get("items_count") or 0):
                    try:
                        children = get("courses/" + course + "/modules/" + str(int(module["id"])) + "/items")
                    except (OSError, ValueError, TypeError):
                        partial = True
                        children = children or []
                for child in children:
                    items.append(row(child, subtitle=str(module.get("name") or "")[:500],
                                     kind=str(child.get("type") or ""),
                                     url=safe_link(child.get("html_url") or child.get("external_url"), base)))
            try:
                for f in get("courses/" + course + "/files"):
                    if not f.get("locked_for_user") and not f.get("hidden_for_user"):
                        items.append(row(f, title=str(f.get("display_name") or f.get("filename") or "File")[:500],
                                         kind="File", url=base + "/courses/" + course + "/files/" + str(int(f["id"]))))
            except (OSError, ValueError, TypeError):
                partial = True
        elif section == "calendar":
            today = datetime.now().date()
            start = today - timedelta(days=today.weekday())
            params = {"start_date": start.isoformat(), "end_date": (start + timedelta(days=7)).isoformat(), "type": "event"}
            if course:
                params["context_codes[]"] = "course_" + course
            for e in get("calendar_events", **params):
                items.append(row(e, startAt=e.get("start_at"), endAt=e.get("end_at"),
                                 allDay=bool(e.get("all_day")), allDayDate=str(e.get("all_day_date") or "")[:10],
                                 location=str(e.get("location_name") or "")[:500]))
        if section == "assignments":
            items.sort(key=lambda a: a.get("dueAt") or "9999")
        data = {"items": items[:10000], "partial": partial or len(items) > 10000}
        save_cache({"version": 1, "fetchedAt": current, "data": data}, path)
        return {**empty, **data, "ok": True, "stale": False, "updatedAt": current}
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return {**empty, **(data or {}), "ok": data is not None, "stale": True,
                "updatedAt": cache.get("fetchedAt", 0), "error": "unavailable"}


if __name__ == "__main__":
    if "--settings" in sys.argv:
        result = public_settings()
    elif "--configure" in sys.argv:
        try:
            result = configure(json.loads(sys.stdin.readline(16385)))
        except (ValueError, TypeError, AttributeError):
            result = {"ok": False, "error": "invalid_input"}
    elif "--academic" in sys.argv:
        parser = argparse.ArgumentParser()
        parser.add_argument("--academic", required=True)
        parser.add_argument("--course", default="")
        parser.add_argument("--refresh", action="store_true")
        parser.add_argument("--cached", action="store_true")
        args = parser.parse_args()
        result = academic(args.academic, args.course, args.refresh, args.cached)
    else:
        result = status(force="--refresh" in sys.argv)
    print(json.dumps(result, ensure_ascii=False))
