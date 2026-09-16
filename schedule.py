#!/usr/bin/env python3
"""CSV import and recurrence engine for the Recurring Schedule plugin."""

from __future__ import annotations

import argparse
import calendar
import csv
import fcntl
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import unquote, urlparse


SCHEMA_VERSION = 1
MAX_CSV_BYTES = 2 * 1024 * 1024
MAX_ROWS = 1000
MAX_OCCURRENCES = 2000

STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
STATE_FILE = STATE_HOME / "omarchy" / "recurring-schedule" / "schedule.json"
REMINDER_STATE_FILE = STATE_FILE.with_name("reminders.json")
REMINDER_LEAD_MINUTES = 5
REMINDER_RETENTION_DAYS = 7

CANONICAL_FIELDS = {
    "title",
    "weekday",
    "monthday",
    "start_time",
    "end_time",
    "recurrence",
    "start_date",
    "end_date",
    "location",
    "description",
}

HEADER_ALIASES = {
    "titulo": "title",
    "title": "title",
    "nombre": "title",
    "actividad": "title",
    "dia_semana": "weekday",
    "weekday": "weekday",
    "day_of_week": "weekday",
    "dia_mes": "monthday",
    "monthday": "monthday",
    "day_of_month": "monthday",
    "hora_inicio": "start_time",
    "start_time": "start_time",
    "hora_fin": "end_time",
    "end_time": "end_time",
    "repeticion": "recurrence",
    "recurrence": "recurrence",
    "repeat": "recurrence",
    "desde": "start_date",
    "fecha_inicio": "start_date",
    "start_date": "start_date",
    "hasta": "end_date",
    "fecha_fin": "end_date",
    "end_date": "end_date",
    "ubicacion": "location",
    "location": "location",
    "lugar": "location",
    "descripcion": "description",
    "description": "description",
    "notas": "description",
}

RECURRENCE_ALIASES = {
    "una_vez": "once",
    "unica": "once",
    "unico": "once",
    "once": "once",
    "none": "once",
    "semanal": "weekly",
    "weekly": "weekly",
    "quincenal": "biweekly",
    "cada_2_semanas": "biweekly",
    "biweekly": "biweekly",
    "fortnightly": "biweekly",
    "mensual": "monthly",
    "monthly": "monthly",
}

WEEKDAY_NAMES = [
    "lunes",
    "martes",
    "miercoles",
    "jueves",
    "viernes",
    "sabado",
    "domingo",
]

WEEKDAY_ALIASES = {
    "lunes": 0,
    "lun": 0,
    "monday": 0,
    "mon": 0,
    "martes": 1,
    "mar": 1,
    "tuesday": 1,
    "tue": 1,
    "miercoles": 2,
    "mie": 2,
    "wednesday": 2,
    "wed": 2,
    "jueves": 3,
    "jue": 3,
    "thursday": 3,
    "thu": 3,
    "viernes": 4,
    "vie": 4,
    "friday": 4,
    "fri": 4,
    "sabado": 5,
    "sab": 5,
    "saturday": 5,
    "sat": 5,
    "domingo": 6,
    "dom": 6,
    "sunday": 6,
    "sun": 6,
}


class ScheduleError(Exception):
    """Expected user-facing import or storage error."""


def normalize_token(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = text.strip().lower()
    return re.sub(r"[^a-z0-9]+", "_", text).strip("_")


def source_path(raw_value: str) -> Path:
    value = str(raw_value or "").strip()
    if value.startswith("file:"):
        parsed = urlparse(value)
        if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
            raise ScheduleError("Only local CSV files can be imported.")
        value = unquote(parsed.path)
    path = Path(value).expanduser()
    try:
        path = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise ScheduleError(f"CSV file not found: {value}") from error
    if not path.is_file():
        raise ScheduleError(f"Not a regular file: {path}")
    if path.suffix.lower() != ".csv":
        raise ScheduleError("The selected file must use the .csv extension.")
    if path.stat().st_size > MAX_CSV_BYTES:
        raise ScheduleError("The CSV file is larger than 2 MiB.")
    return path


def choose_csv() -> dict[str, Any]:
    terminal = shutil.which("xdg-terminal-exec")
    yazi = shutil.which("yazi")
    if not terminal or not yazi:
        raise ScheduleError(
            "The file picker requires xdg-terminal-exec and yazi; enter the CSV path manually."
        )

    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
    fd, chooser_name = tempfile.mkstemp(prefix="schedule-chooser-", dir=runtime_dir)
    os.close(fd)
    chooser_file = Path(chooser_name)
    chooser_file.unlink(missing_ok=True)

    try:
        subprocess.run(
            [
                terminal,
                "--title=Recurring Schedule - CSV",
                f"--dir={Path.home()}",
                "--",
                yazi,
                f"--chooser-file={chooser_file}",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if not chooser_file.exists():
            return {"ok": False, "cancelled": True}
        choices = [line.strip() for line in chooser_file.read_text(encoding="utf-8").splitlines() if line.strip()]
        if not choices:
            return {"ok": False, "cancelled": True}
        selected = source_path(choices[0])
        return {"ok": True, "path": str(selected), "sourceName": selected.name}
    finally:
        chooser_file.unlink(missing_ok=True)


def read_csv_text(path: Path) -> tuple[str, str]:
    raw = path.read_bytes()
    if b"\x00" in raw:
        raise ScheduleError("The CSV file contains binary data.")
    try:
        return raw.decode("utf-8-sig"), "utf-8"
    except UnicodeDecodeError:
        return raw.decode("latin-1"), "latin-1"


def csv_dialect(text: str) -> csv.Dialect:
    sample = text[:8192]
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        delimiter = ";" if sample.count(";") > sample.count(",") else ","

        class Fallback(csv.excel):
            pass

        Fallback.delimiter = delimiter
        return Fallback()


def parse_iso_date(value: str, label: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise ScheduleError(f"{label} must use YYYY-MM-DD.") from error


def parse_time(value: str, label: str) -> str:
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", value)
    if not match:
        raise ScheduleError(f"{label} must use HH:MM.")
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        raise ScheduleError(f"{label} is outside the 24-hour clock.")
    return f"{hour:02d}:{minute:02d}"


def bounded_text(value: Any, label: str, limit: int, required: bool = False) -> str:
    text = str(value or "").strip()
    if required and not text:
        raise ScheduleError(f"{label} is required.")
    if len(text) > limit:
        raise ScheduleError(f"{label} is longer than {limit} characters.")
    return text


def stable_id(item: dict[str, Any], row_number: int) -> str:
    identity = {key: item[key] for key in sorted(item) if key not in ("id", "sourceRow")}
    payload = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(f"{row_number}:{payload}".encode("utf-8")).hexdigest()[:16]


def normalize_row(values: dict[str, str], row_number: int) -> dict[str, Any]:
    title = bounded_text(values.get("title"), "titulo", 200, required=True)
    recurrence_token = normalize_token(values.get("recurrence"))
    recurrence = RECURRENCE_ALIASES.get(recurrence_token)
    if recurrence is None:
        raise ScheduleError(
            "repeticion must be una_vez, semanal, quincenal, or mensual."
        )

    start_text = bounded_text(values.get("start_date"), "desde", 10, required=True)
    start_date = parse_iso_date(start_text, "desde")
    end_text = bounded_text(values.get("end_date"), "hasta", 10)
    end_date = parse_iso_date(end_text, "hasta") if end_text else None
    if end_date and end_date < start_date:
        raise ScheduleError("hasta cannot be earlier than desde.")
    if recurrence == "once" and end_date and end_date != start_date:
        raise ScheduleError("For una_vez, hasta must be empty or equal to desde.")

    start_time = parse_time(
        bounded_text(values.get("start_time"), "hora_inicio", 5, required=True),
        "hora_inicio",
    )
    end_time = parse_time(
        bounded_text(values.get("end_time"), "hora_fin", 5, required=True),
        "hora_fin",
    )
    if end_time <= start_time:
        raise ScheduleError("hora_fin must be later than hora_inicio.")

    weekday: int | None = None
    monthday: int | None = None
    if recurrence in ("weekly", "biweekly"):
        weekday_text = normalize_token(values.get("weekday"))
        if weekday_text:
            weekday = WEEKDAY_ALIASES.get(weekday_text)
            if weekday is None:
                raise ScheduleError("dia_semana is not a recognized weekday.")
        else:
            weekday = start_date.weekday()
    elif recurrence == "monthly":
        monthday_text = normalize_token(values.get("monthday"))
        if monthday_text in ("ultimo", "ultima", "last"):
            monthday = -1
        elif monthday_text:
            try:
                monthday = int(monthday_text)
            except ValueError as error:
                raise ScheduleError("dia_mes must be a number from 1 to 31 or ultimo.") from error
            if monthday < 1 or monthday > 31:
                raise ScheduleError("dia_mes must be a number from 1 to 31 or ultimo.")
        else:
            monthday = start_date.day

    item: dict[str, Any] = {
        "title": title,
        "weekday": weekday,
        "monthday": monthday,
        "startTime": start_time,
        "endTime": end_time,
        "recurrence": recurrence,
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat() if end_date else None,
        "location": bounded_text(values.get("location"), "ubicacion", 300),
        "description": bounded_text(values.get("description"), "descripcion", 1000),
        "sourceRow": row_number,
    }
    item["id"] = stable_id(item, row_number)
    return item


def parse_csv(raw_path: str) -> dict[str, Any]:
    path = source_path(raw_path)
    text, encoding = read_csv_text(path)
    dialect = csv_dialect(text)
    reader = csv.DictReader(io.StringIO(text, newline=""), dialect=dialect)
    if not reader.fieldnames:
        raise ScheduleError("The CSV file has no header row.")

    mapped_headers: dict[str, str] = {}
    unknown_headers: list[str] = []
    duplicate_fields: list[str] = []
    for original in reader.fieldnames:
        key = normalize_token(original)
        canonical = HEADER_ALIASES.get(key)
        if not canonical:
            if str(original or "").strip():
                unknown_headers.append(str(original).strip())
            continue
        if canonical in mapped_headers.values():
            duplicate_fields.append(canonical)
        mapped_headers[str(original)] = canonical

    errors: list[dict[str, Any]] = []
    warnings: list[str] = []
    required = {"title", "start_time", "end_time", "recurrence", "start_date"}
    missing = sorted(required - set(mapped_headers.values()))
    if missing:
        errors.append({"row": 1, "message": "Missing required columns: " + ", ".join(missing)})
    if duplicate_fields:
        errors.append({"row": 1, "message": "Duplicate columns: " + ", ".join(sorted(set(duplicate_fields)))})
    if unknown_headers:
        warnings.append("Ignored columns: " + ", ".join(unknown_headers))
    if encoding != "utf-8":
        warnings.append("The file was decoded as Latin-1; UTF-8 is recommended.")

    items: list[dict[str, Any]] = []
    if not errors:
        for row_number, raw_row in enumerate(reader, start=2):
            if row_number > MAX_ROWS + 1:
                errors.append({"row": row_number, "message": f"The file exceeds {MAX_ROWS} data rows."})
                break
            if not any(str(value or "").strip() for value in raw_row.values()):
                continue
            values = {
                canonical: str(raw_row.get(original) or "").strip()
                for original, canonical in mapped_headers.items()
            }
            try:
                items.append(normalize_row(values, row_number))
            except ScheduleError as error:
                errors.append({"row": row_number, "message": str(error)})

    if not items and not errors:
        errors.append({"row": 1, "message": "The CSV file contains no activities."})

    return {
        "ok": bool(items) and not errors,
        "source": str(path),
        "sourceName": path.name,
        "delimiter": "tab" if dialect.delimiter == "\t" else dialect.delimiter,
        "items": items,
        "validCount": len(items),
        "errors": errors,
        "warnings": warnings,
    }


def occurs_on(item: dict[str, Any], current: date) -> bool:
    start = date.fromisoformat(item["startDate"])
    if current < start:
        return False
    end_value = item.get("endDate")
    if end_value and current > date.fromisoformat(end_value):
        return False

    recurrence = item.get("recurrence")
    if recurrence == "once":
        return current == start
    if recurrence == "weekly":
        return current.weekday() == int(item["weekday"])
    if recurrence == "biweekly":
        if current.weekday() != int(item["weekday"]):
            return False
        first = start + timedelta(days=(int(item["weekday"]) - start.weekday()) % 7)
        return ((current - first).days // 7) % 2 == 0
    if recurrence == "monthly":
        monthday = int(item["monthday"])
        target = calendar.monthrange(current.year, current.month)[1] if monthday == -1 else monthday
        return current.day == target
    return False


def expand_occurrences(
    items: list[dict[str, Any]], start: date, end: date
) -> list[dict[str, Any]]:
    if end < start:
        return []
    if (end - start).days > 3660:
        raise ScheduleError("The requested occurrence window is too large.")

    occurrences: list[dict[str, Any]] = []
    current = start
    while current <= end and len(occurrences) < MAX_OCCURRENCES:
        for item in items:
            if occurs_on(item, current):
                occurrences.append(
                    {
                        "id": f"{item['id']}:{current.isoformat()}",
                        "scheduleId": item["id"],
                        "date": current.isoformat(),
                        "title": item["title"],
                        "startTime": item["startTime"],
                        "endTime": item["endTime"],
                        "recurrence": item["recurrence"],
                        "location": item.get("location", ""),
                        "description": item.get("description", ""),
                    }
                )
                if len(occurrences) >= MAX_OCCURRENCES:
                    break
        current += timedelta(days=1)

    occurrences.sort(key=lambda event: (event["date"], event["startTime"], event["title"].casefold()))
    return occurrences


def event_is_active(event: dict[str, Any], now: datetime) -> bool:
    if event.get("date") != now.date().isoformat():
        return False
    try:
        start_hour, start_minute = (int(part) for part in event["startTime"].split(":"))
        end_hour, end_minute = (int(part) for part in event["endTime"].split(":"))
    except (KeyError, TypeError, ValueError):
        return False
    current_minutes = now.hour * 60 + now.minute
    start_minutes = start_hour * 60 + start_minute
    end_minutes = end_hour * 60 + end_minute
    return start_minutes <= current_minutes < end_minutes


def local_datetime(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone().replace(tzinfo=None)


def event_start_datetime(event: dict[str, Any]) -> datetime:
    try:
        return datetime.strptime(
            f"{event['date']} {event['startTime']}", "%Y-%m-%d %H:%M"
        )
    except (KeyError, TypeError, ValueError) as error:
        raise ScheduleError("A saved activity has an invalid start time.") from error


def due_reminder_events(
    items: list[dict[str, Any]],
    now: datetime,
    lead_minutes: int = REMINDER_LEAD_MINUTES,
) -> list[dict[str, Any]]:
    current = local_datetime(now)
    events = expand_occurrences(
        items, current.date(), current.date() + timedelta(days=1)
    )
    lead = timedelta(minutes=lead_minutes)
    return [
        event
        for event in events
        if event_start_datetime(event) - lead <= current < event_start_datetime(event)
    ]


def empty_store() -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "source": "",
        "sourceName": "",
        "importedAt": "",
        "items": [],
    }


def load_store(path: Path = STATE_FILE) -> dict[str, Any]:
    if not path.exists():
        return empty_store()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ScheduleError("The saved schedule could not be read.") from error
    if not isinstance(payload, dict) or payload.get("schemaVersion") != SCHEMA_VERSION:
        raise ScheduleError("The saved schedule uses an unsupported format.")
    if not isinstance(payload.get("items"), list):
        raise ScheduleError("The saved schedule has invalid activities.")
    return payload


def save_payload(payload: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    data = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    fd, temporary_name = tempfile.mkstemp(prefix=".schedule-", suffix=".json", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def save_store(payload: dict[str, Any], path: Path = STATE_FILE) -> None:
    save_payload(payload, path)


def load_reminder_state(path: Path = REMINDER_STATE_FILE) -> dict[str, Any]:
    if not path.exists():
        return {"schemaVersion": 1, "sent": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ScheduleError("The reminder history could not be read.") from error
    if (
        not isinstance(payload, dict)
        or payload.get("schemaVersion") != 1
        or not isinstance(payload.get("sent"), dict)
    ):
        raise ScheduleError("The reminder history uses an unsupported format.")
    return payload


def send_class_notification(
    event: dict[str, Any], lead_minutes: int = REMINDER_LEAD_MINUTES
) -> None:
    omarchy = shutil.which("omarchy")
    if not omarchy:
        raise ScheduleError("The Omarchy notification command is unavailable.")
    details = f"{event['title']}\n{event['startTime']} - {event['endTime']}"
    if event.get("location"):
        details += f" | {event['location']}"
    try:
        subprocess.run(
            [
                omarchy,
                "notification",
                "send",
                "--app-name",
                "Recurring Schedule",
                "-u",
                "normal",
                "-i",
                "calendar",
                "-t",
                "10000",
                f"Clase en {lead_minutes} minutos",
                details,
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ScheduleError(f"The class notification could not be sent: {error}") from error


def notify_due_classes(
    store: dict[str, Any],
    now: datetime | None = None,
    state_path: Path = REMINDER_STATE_FILE,
    notifier: Callable[[dict[str, Any], int], None] = send_class_notification,
) -> dict[str, Any]:
    current = local_datetime(now or datetime.now())
    state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)

    with os.fdopen(lock_fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_reminder_state(state_path)
        sent = state["sent"]
        cutoff = current.date() - timedelta(days=REMINDER_RETENTION_DAYS)
        retained: dict[str, str] = {}
        for occurrence_id, sent_at in sent.items():
            try:
                occurrence_date = date.fromisoformat(str(occurrence_id).rsplit(":", 1)[1])
            except (IndexError, ValueError):
                continue
            if occurrence_date >= cutoff:
                retained[str(occurrence_id)] = str(sent_at)

        notified: list[dict[str, Any]] = []
        errors: list[dict[str, Any]] = []
        for event in due_reminder_events(store.get("items", []), current):
            if event["id"] in retained:
                continue
            try:
                notifier(event, REMINDER_LEAD_MINUTES)
            except ScheduleError as error:
                errors.append({"row": 0, "message": str(error)})
                continue
            retained[event["id"]] = current.isoformat(timespec="seconds")
            notified.append(event)

        if retained != sent:
            save_payload({"schemaVersion": 1, "sent": retained}, state_path)

    return {
        "ok": not errors,
        "notifiedCount": len(notified),
        "notified": notified,
        "errors": errors,
    }


def status_payload(
    store: dict[str, Any],
    today: date | None = None,
    days: int = 120,
    now: datetime | None = None,
) -> dict[str, Any]:
    reference_now = now or datetime.now()
    current = today or reference_now.date()
    if today is not None and now is None:
        reference_now = datetime.combine(today, reference_now.time())
    window_days = min(max(int(days), 1), 3660)
    items = store.get("items", [])
    events = expand_occurrences(items, current, current + timedelta(days=window_days))
    for event in events:
        event["active"] = event_is_active(event, reference_now)
    today_key = current.isoformat()
    active_events = [event for event in events if event["active"]]
    return {
        "ok": True,
        "configured": bool(items),
        "source": store.get("source", ""),
        "sourceName": store.get("sourceName", ""),
        "importedAt": store.get("importedAt", ""),
        "itemCount": len(items),
        "todayCount": sum(1 for event in events if event["date"] == today_key),
        "activeCount": len(active_events),
        "activeTitle": active_events[0]["title"] if active_events else "",
        "events": events,
    }


def import_csv(raw_path: str, state_path: Path = STATE_FILE) -> tuple[dict[str, Any], int]:
    preview = parse_csv(raw_path)
    if not preview["ok"]:
        return preview, 2
    store = {
        "schemaVersion": SCHEMA_VERSION,
        "source": preview["source"],
        "sourceName": preview["sourceName"],
        "importedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "items": preview["items"],
    }
    save_store(store, state_path)
    result = status_payload(store)
    result["importedCount"] = len(store["items"])
    result["warnings"] = preview["warnings"]
    return result, 0


def print_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preview = commands.add_parser("preview", help="Validate and preview a CSV file")
    preview.add_argument("file")
    importer = commands.add_parser("import", help="Import a validated CSV file")
    importer.add_argument("file")
    status = commands.add_parser("status", help="Show saved schedule status")
    status.add_argument("--date", help="Override today's date (YYYY-MM-DD)")
    status.add_argument("--days", type=int, default=120)
    commands.add_parser("choose", help="Choose a CSV with Yazi in an external terminal")
    commands.add_parser("remind", help="Notify for classes starting in five minutes")
    commands.add_parser("clear", help="Delete the imported schedule")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "preview":
            payload = parse_csv(args.file)
            print_json(payload)
            return 0 if payload["ok"] else 2
        if args.command == "import":
            payload, exit_code = import_csv(args.file)
            print_json(payload)
            return exit_code
        if args.command == "status":
            today = parse_iso_date(args.date, "date") if args.date else date.today()
            print_json(status_payload(load_store(), today=today, days=args.days))
            return 0
        if args.command == "choose":
            payload = choose_csv()
            print_json(payload)
            return 0
        if args.command == "remind":
            payload = notify_due_classes(load_store())
            print_json(payload)
            return 0 if payload["ok"] else 2
        if args.command == "clear":
            STATE_FILE.unlink(missing_ok=True)
            REMINDER_STATE_FILE.unlink(missing_ok=True)
            print_json(status_payload(empty_store()))
            return 0
    except ScheduleError as error:
        print_json({"ok": False, "errors": [{"row": 0, "message": str(error)}]})
        return 2
    except OSError as error:
        print_json({"ok": False, "errors": [{"row": 0, "message": f"File operation failed: {error}"}]})
        return 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
