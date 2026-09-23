#!/usr/bin/env python3
"""CSV import and recurrence engine for the Niku Calendar plugin."""

from __future__ import annotations

import argparse
import calendar
import copy
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
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import quote, unquote, urlparse, urlsplit, urlunsplit


SCHEMA_VERSION = 2
DEFAULT_TITLE = "Schedule"
MAX_CSV_BYTES = 2 * 1024 * 1024
MAX_ROWS = 1000
MAX_OCCURRENCES = 2000
MAX_JSON_BYTES = 1024 * 1024

STATE_HOME = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
STATE_FILE = STATE_HOME / "omarchy" / "recurring-schedule" / "schedule.json"
REMINDER_STATE_FILE = STATE_FILE.with_name("reminders.json")
REMINDER_LEAD_MINUTES = 10
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
    "notes",
}

ACTIVITY_FIELDS = {
    "title",
    "weekday",
    "monthday",
    "startTime",
    "endTime",
    "recurrence",
    "startDate",
    "endDate",
    "location",
    "notes",
    "links",
}
PERSISTED_ACTIVITY_FIELDS = ACTIVITY_FIELDS | {"id", "sourceRow"}
STORE_FIELDS = {
    "schemaVersion",
    "revision",
    "title",
    "source",
    "sourceName",
    "importedAt",
    "items",
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
    "descripcion": "notes",
    "description": "notes",
    "notas": "notes",
    "notes": "notes",
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


BACKEND_MESSAGES = {
    "en": {
        "local_csv_only": "Only local CSV files can be imported.",
        "csv_not_found": "CSV file not found: {value}",
        "not_regular_file": "Not a regular file: {path}",
        "csv_extension": "The selected file must use the .csv extension.",
        "csv_too_large": "The CSV file is larger than 2 MiB.",
        "picker_requirements": "The file picker requires xdg-terminal-exec and yazi; enter the CSV path manually.",
        "picker_title": "Niku Calendar - CSV",
        "csv_binary": "The CSV file contains binary data.",
        "date_format": "{label} must use YYYY-MM-DD.",
        "time_format": "{label} must use HH:MM.",
        "time_24_hour": "{label} is outside the 24-hour clock.",
        "must_be_string": "{label} must be a string.",
        "required": "{label} is required.",
        "too_long": "{label} is longer than {limit} characters.",
        "url_control": "{label} cannot contain control characters.",
        "url_invalid": "{label} is not a valid HTTP(S) URL.",
        "url_complete": "{label} must be a complete HTTP(S) URL with a hostname.",
        "url_credentials": "{label} cannot contain credentials.",
        "url_hostname": "{label} has an invalid hostname.",
        "links_array": "links must be an array.",
        "links_max": "An activity can have at most 10 links.",
        "link_object": "link {index} must be an object.",
        "link_unknown_fields": "link {index} has unknown fields: {names}.",
        "activity_object": "activity must be an object.",
        "id_supply": "id is immutable and cannot be supplied.",
        "unknown_activity_fields": "Unknown activity fields: {names}.",
        "recurrence_values": "{label} must be once, weekly, biweekly, or monthly.",
        "end_before_start": "{end} cannot be earlier than {start}.",
        "once_end": "For once, {end} must be empty or equal to {start}.",
        "end_later": "{end} must be later than {start}.",
        "weekday_range": "{label} must be a weekday from 0 to 6.",
        "monthday_range": "{label} must be a number from 1 to 31 or -1.",
        "saved_invalid_id": "A saved activity has an invalid id.",
        "activity_id_required": "An activity id is required.",
        "source_row": "sourceRow must be a positive integer.",
        "csv_no_header": "The CSV file has no header row.",
        "missing_columns": "Missing required columns: {names}",
        "duplicate_columns": "Duplicate columns: {names}",
        "ignored_columns": "Ignored columns: {names}",
        "extra_columns": "The row has more values than the header. Quote values that contain the delimiter.",
        "latin1": "The file was decoded as Latin-1; UTF-8 is recommended.",
        "row_limit": "The file exceeds {limit} data rows.",
        "csv_empty": "The CSV file contains no activities.",
        "occurrence_window": "The requested occurrence window is too large.",
        "saved_start_time": "A saved activity has an invalid start time.",
        "store_unsupported": "The saved schedule uses an unsupported format.",
        "store_missing_fields": "The saved schedule is missing fields: {names}.",
        "store_unknown_fields": "The saved schedule has unknown fields: {names}.",
        "store_invalid_revision": "The saved schedule has an invalid revision.",
        "store_invalid_metadata": "The saved schedule has an invalid {field} value.",
        "store_invalid_activities": "The saved schedule has invalid activities.",
        "store_duplicate_ids": "The saved schedule contains duplicate activity ids.",
        "store_read": "The saved schedule could not be read.",
        "expected_revision": "expectedRevision must be a non-negative integer.",
        "revision_conflict": "Revision conflict: expected {expected}, current {current}. Refresh and try again.",
        "link_scope": "linkScope must be activity or same-title.",
        "links_scope": "links are required when linkScope is same-title.",
        "changes_object": "changes must be an object.",
        "id_edit": "id is immutable and cannot be edited.",
        "empty_changes": "At least one activity field must be updated.",
        "activity_not_found": "Activity not found: {activity_id}",
        "reminder_read": "The reminder history could not be read.",
        "reminder_format": "The reminder history uses an unsupported format.",
        "notification_unavailable": "The Omarchy notification command is unavailable.",
        "notification_app": "Niku Calendar",
        "notification_one": "Activity in 1 minute",
        "notification_other": "Activity in {minutes} minutes",
        "notification_failed": "The activity notification could not be sent: {error}",
        "schedule_required": "A schedule is required for reminder processing.",
        "json_too_large": "The JSON payload is too large.",
        "json_invalid": "stdin must contain a valid JSON object.",
        "json_object": "stdin must contain a JSON object.",
        "unknown_payload_fields": "Unknown payload fields: {names}.",
        "missing_payload_fields": "Missing payload fields: {names}.",
        "file_operation": "File operation failed: {error}",
        "field_schedule_title": "schedule title",
        "field_title": "title",
        "field_weekday": "weekday",
        "field_monthday": "monthday",
        "field_startTime": "start time",
        "field_endTime": "end time",
        "field_recurrence": "recurrence",
        "field_startDate": "start date",
        "field_endDate": "end date",
        "field_location": "location",
        "field_notes": "notes",
        "field_link_url": "link url",
        "field_link_label": "link {index} label",
        "field_date": "date",
        "cli_description": "CSV import and recurrence engine for the Niku Calendar plugin.",
        "cli_language": "Language for messages, the file picker, and notifications",
        "cli_preview": "Validate and preview a CSV file",
        "cli_import": "Import a validated CSV file",
        "cli_expected_revision": "Reject the replacement unless the saved revision matches",
        "cli_status": "Show saved schedule status",
        "cli_date": "Override today's date (YYYY-MM-DD)",
        "cli_rename": "Rename the schedule from a stdin JSON payload",
        "cli_create": "Create an activity from a stdin JSON payload",
        "cli_update": "Update an activity by ID using a stdin JSON payload",
        "cli_delete": "Delete an activity by ID using a stdin JSON payload",
        "cli_choose": "Choose a CSV with Yazi in an external terminal",
        "cli_remind": "Notify for activities starting in ten minutes",
        "cli_clear": "Delete the imported schedule",
    },
    "es": {
        "local_csv_only": "Solo se pueden importar archivos CSV locales.",
        "csv_not_found": "No se encontró el archivo CSV: {value}",
        "not_regular_file": "No es un archivo normal: {path}",
        "csv_extension": "El archivo seleccionado debe usar la extensión .csv.",
        "csv_too_large": "El archivo CSV supera los 2 MiB.",
        "picker_requirements": "El selector de archivos requiere xdg-terminal-exec y yazi; introduce la ruta del CSV manualmente.",
        "picker_title": "Niku Calendar - CSV",
        "csv_binary": "El archivo CSV contiene datos binarios.",
        "date_format": "{label} debe usar AAAA-MM-DD.",
        "time_format": "{label} debe usar HH:MM.",
        "time_24_hour": "{label} está fuera del formato de 24 horas.",
        "must_be_string": "{label} debe ser texto.",
        "required": "Se requiere {label}.",
        "too_long": "{label} supera los {limit} caracteres.",
        "url_control": "{label} no puede contener caracteres de control.",
        "url_invalid": "{label} no es una URL HTTP(S) válida.",
        "url_complete": "{label} debe ser una URL HTTP(S) completa con nombre de host.",
        "url_credentials": "{label} no puede contener credenciales.",
        "url_hostname": "{label} tiene un nombre de host inválido.",
        "links_array": "los enlaces deben ser una lista.",
        "links_max": "Una actividad puede tener como máximo 10 enlaces.",
        "link_object": "el enlace {index} debe ser un objeto.",
        "link_unknown_fields": "el enlace {index} tiene campos desconocidos: {names}.",
        "activity_object": "la actividad debe ser un objeto.",
        "id_supply": "el id es inmutable y no puede proporcionarse.",
        "unknown_activity_fields": "Campos de actividad desconocidos: {names}.",
        "recurrence_values": "{label} debe ser una vez, semanal, quincenal o mensual.",
        "end_before_start": "{end} no puede ser anterior a {start}.",
        "once_end": "Para una sola vez, {end} debe estar vacío o ser igual a {start}.",
        "end_later": "{end} debe ser posterior a {start}.",
        "weekday_range": "{label} debe ser un día de la semana entre 0 y 6.",
        "monthday_range": "{label} debe ser un número entre 1 y 31, o -1.",
        "saved_invalid_id": "Una actividad guardada tiene un id inválido.",
        "activity_id_required": "Se requiere un id de actividad.",
        "source_row": "sourceRow debe ser un entero positivo.",
        "csv_no_header": "El archivo CSV no tiene fila de encabezados.",
        "missing_columns": "Faltan columnas obligatorias: {names}",
        "duplicate_columns": "Columnas duplicadas: {names}",
        "ignored_columns": "Columnas ignoradas: {names}",
        "extra_columns": "La fila tiene más valores que el encabezado. Escribe entre comillas los valores que contengan el delimitador.",
        "latin1": "El archivo se decodificó como Latin-1; se recomienda UTF-8.",
        "row_limit": "El archivo supera las {limit} filas de datos.",
        "csv_empty": "El archivo CSV no contiene actividades.",
        "occurrence_window": "El intervalo de ocurrencias solicitado es demasiado grande.",
        "saved_start_time": "Una actividad guardada tiene una hora de inicio inválida.",
        "store_unsupported": "El horario guardado usa un formato no compatible.",
        "store_missing_fields": "Al horario guardado le faltan campos: {names}.",
        "store_unknown_fields": "El horario guardado tiene campos desconocidos: {names}.",
        "store_invalid_revision": "El horario guardado tiene una revisión inválida.",
        "store_invalid_metadata": "El horario guardado tiene un valor {field} inválido.",
        "store_invalid_activities": "El horario guardado contiene actividades inválidas.",
        "store_duplicate_ids": "El horario guardado contiene ids de actividad duplicados.",
        "store_read": "No se pudo leer el horario guardado.",
        "expected_revision": "expectedRevision debe ser un entero no negativo.",
        "revision_conflict": "Conflicto de revisión: se esperaba {expected}, la actual es {current}. Actualiza e inténtalo de nuevo.",
        "link_scope": "linkScope debe ser activity o same-title.",
        "links_scope": "se requieren enlaces cuando linkScope es same-title.",
        "changes_object": "los cambios deben ser un objeto.",
        "id_edit": "el id es inmutable y no se puede editar.",
        "empty_changes": "Debe actualizarse al menos un campo de la actividad.",
        "activity_not_found": "No se encontró la actividad: {activity_id}",
        "reminder_read": "No se pudo leer el historial de recordatorios.",
        "reminder_format": "El historial de recordatorios usa un formato no compatible.",
        "notification_unavailable": "El comando de notificaciones de Omarchy no está disponible.",
        "notification_app": "Niku Calendar",
        "notification_one": "Actividad en 1 minuto",
        "notification_other": "Actividad en {minutes} minutos",
        "notification_failed": "No se pudo enviar la notificación de la actividad: {error}",
        "schedule_required": "Se requiere un horario para procesar los recordatorios.",
        "json_too_large": "El contenido JSON es demasiado grande.",
        "json_invalid": "stdin debe contener un objeto JSON válido.",
        "json_object": "stdin debe contener un objeto JSON.",
        "unknown_payload_fields": "Campos desconocidos en el contenido: {names}.",
        "missing_payload_fields": "Faltan campos en el contenido: {names}.",
        "file_operation": "Falló la operación de archivo: {error}",
        "field_schedule_title": "el título del horario",
        "field_title": "el título",
        "field_weekday": "el día de la semana",
        "field_monthday": "el día del mes",
        "field_startTime": "la hora de inicio",
        "field_endTime": "la hora de fin",
        "field_recurrence": "la repetición",
        "field_startDate": "la fecha de inicio",
        "field_endDate": "la fecha de fin",
        "field_location": "la ubicación",
        "field_notes": "las notas",
        "field_link_url": "la URL del enlace",
        "field_link_label": "la etiqueta del enlace {index}",
        "field_date": "la fecha",
        "cli_description": "Motor de importación CSV y recurrencias para el plugin Niku Calendar.",
        "cli_language": "Idioma de los mensajes, el selector de archivos y las notificaciones",
        "cli_preview": "Validar y previsualizar un archivo CSV",
        "cli_import": "Importar un archivo CSV validado",
        "cli_expected_revision": "Rechazar el reemplazo si la revisión guardada no coincide",
        "cli_status": "Mostrar el estado del horario guardado",
        "cli_date": "Usar otra fecha actual (AAAA-MM-DD)",
        "cli_rename": "Renombrar el horario mediante un contenido JSON por stdin",
        "cli_create": "Crear una actividad mediante un contenido JSON por stdin",
        "cli_update": "Actualizar una actividad por id mediante un contenido JSON por stdin",
        "cli_delete": "Eliminar una actividad por id mediante un contenido JSON por stdin",
        "cli_choose": "Elegir un CSV con Yazi en una terminal externa",
        "cli_remind": "Notificar las actividades que empiezan en diez minutos",
        "cli_clear": "Eliminar el horario importado",
    },
}

CURRENT_LANGUAGE = "en"

CSV_FIELD_LABELS = {
    "en": {
        "title": "title",
        "weekday": "weekday",
        "monthday": "monthday",
        "start_time": "start_time",
        "end_time": "end_time",
        "recurrence": "recurrence",
        "start_date": "start_date",
        "end_date": "end_date",
        "location": "location",
        "notes": "description",
    },
    "es": {
        "title": "titulo",
        "weekday": "dia_semana",
        "monthday": "dia_mes",
        "start_time": "hora_inicio",
        "end_time": "hora_fin",
        "recurrence": "repeticion",
        "start_date": "desde",
        "end_date": "hasta",
        "location": "ubicacion",
        "notes": "descripcion",
    },
}


def set_language(value: str) -> str:
    global CURRENT_LANGUAGE
    CURRENT_LANGUAGE = "es" if str(value).lower() == "es" else "en"
    return CURRENT_LANGUAGE


def message(key: str, **values: Any) -> str:
    template = BACKEND_MESSAGES.get(CURRENT_LANGUAGE, {}).get(key)
    if template is None:
        template = BACKEND_MESSAGES["en"].get(key, key)
    return template.format(**values)


def csv_field_names(fields: list[str]) -> str:
    labels = CSV_FIELD_LABELS.get(CURRENT_LANGUAGE, CSV_FIELD_LABELS["en"])
    return ", ".join(labels.get(field, field) for field in fields)


class ScheduleError(Exception):
    """Expected user-facing import or storage error."""

    def __init__(self, key: str, *, code: str | None = None, **values: Any):
        self.key = key
        self.code = code or key
        self.values = values
        super().__init__(message(key, **values))


def error_issue(error: ScheduleError, row: int = 0) -> dict[str, Any]:
    return {"row": row, "code": error.code, "message": str(error)}


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
            raise ScheduleError("local_csv_only")
        value = unquote(parsed.path)
    path = Path(value).expanduser()
    try:
        path = path.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise ScheduleError("csv_not_found", value=value) from error
    if not path.is_file():
        raise ScheduleError("not_regular_file", path=path)
    if path.suffix.lower() != ".csv":
        raise ScheduleError("csv_extension")
    if path.stat().st_size > MAX_CSV_BYTES:
        raise ScheduleError("csv_too_large")
    return path


def choose_csv() -> dict[str, Any]:
    terminal = shutil.which("xdg-terminal-exec")
    yazi = shutil.which("yazi")
    if not terminal or not yazi:
        raise ScheduleError("picker_requirements")

    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
    fd, chooser_name = tempfile.mkstemp(prefix="schedule-chooser-", dir=runtime_dir)
    os.close(fd)
    chooser_file = Path(chooser_name)
    chooser_file.unlink(missing_ok=True)

    try:
        subprocess.run(
            [
                terminal,
                f"--title={message('picker_title')}",
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
        raise ScheduleError("csv_binary")
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
        raise ScheduleError("date_format", label=label) from error


def parse_time(value: str, label: str) -> str:
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", value)
    if not match:
        raise ScheduleError("time_format", label=label)
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        raise ScheduleError("time_24_hour", label=label)
    return f"{hour:02d}:{minute:02d}"


def bounded_text(value: Any, label: str, limit: int, required: bool = False) -> str:
    if value is None:
        text = ""
    elif not isinstance(value, str):
        raise ScheduleError("must_be_string", label=label)
    else:
        text = value.strip()
    if required and not text:
        raise ScheduleError("required", label=label)
    if len(text) > limit:
        raise ScheduleError("too_long", label=label, limit=limit)
    return text


def normalize_schedule_title(value: Any) -> str:
    return bounded_text(
        value, message("field_schedule_title"), 200, required=True
    )


def has_control_characters(value: str) -> bool:
    return any(unicodedata.category(char) == "Cc" for char in value)


def normalize_http_url(value: Any) -> str:
    label = message("field_link_url")
    if not isinstance(value, str):
        raise ScheduleError("must_be_string", label=label)
    if has_control_characters(value):
        raise ScheduleError("url_control", label=label)
    text = bounded_text(value, label, 2048, required=True)
    try:
        parsed = urlsplit(text)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise ScheduleError("url_invalid", label=label) from error
    scheme = parsed.scheme.lower()
    if scheme not in ("http", "https") or not parsed.netloc or not hostname:
        raise ScheduleError("url_complete", label=label)
    if parsed.username is not None or parsed.password is not None:
        raise ScheduleError("url_credentials", label=label)
    if any(char.isspace() or has_control_characters(char) for char in hostname):
        raise ScheduleError("url_hostname", label=label)

    if ":" in hostname:
        normalized_host = f"[{hostname.lower()}]"
    else:
        try:
            normalized_host = hostname.encode("idna").decode("ascii").lower()
        except UnicodeError as error:
            raise ScheduleError("url_hostname", label=label) from error
        labels = normalized_host.rstrip(".").split(".")
        if any(
            not label
            or len(label) > 63
            or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
            for label in labels
        ):
            raise ScheduleError("url_hostname", label=label)

    default_port = (scheme == "http" and port == 80) or (
        scheme == "https" and port == 443
    )
    netloc = normalized_host if port is None or default_port else f"{normalized_host}:{port}"
    normalized = urlunsplit(
        (
            scheme,
            netloc,
            quote(parsed.path, safe="/%:@!$&'()*+,;=-._~"),
            quote(parsed.query, safe="/?@!$&'()*+,;=:-._~%"),
            quote(parsed.fragment, safe="/?@!$&'()*+,;=:-._~%"),
        )
    )
    if len(normalized) > 2048:
        raise ScheduleError("too_long", label=label, limit=2048)
    return normalized


def normalize_links(value: Any) -> list[dict[str, str]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ScheduleError("links_array")
    if len(value) > 10:
        raise ScheduleError("links_max")

    links: list[dict[str, str]] = []
    for index, link in enumerate(value, start=1):
        if not isinstance(link, dict):
            raise ScheduleError("link_object", index=index)
        unknown = set(link) - {"label", "url"}
        if unknown:
            names = ", ".join(sorted(str(key) for key in unknown))
            raise ScheduleError("link_unknown_fields", index=index, names=names)
        links.append(
            {
                "label": bounded_text(
                    link.get("label"),
                    message("field_link_label", index=index),
                    80,
                    required=True,
                ),
                "url": normalize_http_url(link.get("url")),
            }
        )
    return links


def valid_activity_id(value: Any) -> bool:
    return isinstance(value, str) and bool(value)


def normalize_activity(
    values: dict[str, Any],
    *,
    persisted: bool = False,
    generate_id: bool = False,
    labels: dict[str, str] | None = None,
) -> dict[str, Any]:
    if not isinstance(values, dict):
        raise ScheduleError("activity_object")
    if "id" in values and not persisted:
        raise ScheduleError("id_supply")

    allowed = PERSISTED_ACTIVITY_FIELDS if persisted else ACTIVITY_FIELDS
    unknown = set(values) - allowed
    if unknown:
        names = ", ".join(sorted(str(key) for key in unknown))
        raise ScheduleError("unknown_activity_fields", names=names)

    field_labels = labels or {}

    def label(name: str) -> str:
        return field_labels.get(name, message(f"field_{name}"))

    title = bounded_text(values.get("title"), label("title"), 200, required=True)
    recurrence_text = bounded_text(
        values.get("recurrence"), label("recurrence"), 30, required=True
    )
    recurrence = RECURRENCE_ALIASES.get(normalize_token(recurrence_text))
    if recurrence is None:
        raise ScheduleError("recurrence_values", label=label("recurrence"))

    start_text = bounded_text(
        values.get("startDate"), label("startDate"), 10, required=True
    )
    start_date = parse_iso_date(start_text, label("startDate"))
    end_text = bounded_text(values.get("endDate"), label("endDate"), 10)
    end_date = parse_iso_date(end_text, label("endDate")) if end_text else None
    if end_date and end_date < start_date:
        raise ScheduleError(
            "end_before_start", end=label("endDate"), start=label("startDate")
        )
    if recurrence == "once" and end_date and end_date != start_date:
        raise ScheduleError(
            "once_end", end=label("endDate"), start=label("startDate")
        )

    start_time = parse_time(
        bounded_text(
            values.get("startTime"), label("startTime"), 5, required=True
        ),
        label("startTime"),
    )
    end_time = parse_time(
        bounded_text(values.get("endTime"), label("endTime"), 5, required=True),
        label("endTime"),
    )
    if end_time <= start_time:
        raise ScheduleError(
            "end_later", end=label("endTime"), start=label("startTime")
        )

    weekday: int | None = None
    monthday: int | None = None
    if recurrence in ("weekly", "biweekly"):
        raw_weekday = values.get("weekday")
        if raw_weekday in (None, ""):
            weekday = start_date.weekday()
        elif isinstance(raw_weekday, bool):
            raise ScheduleError("weekday_range", label=label("weekday"))
        elif isinstance(raw_weekday, int):
            weekday = raw_weekday
        elif isinstance(raw_weekday, str):
            weekday = WEEKDAY_ALIASES.get(normalize_token(raw_weekday))
            if weekday is None and raw_weekday.strip().isdigit():
                weekday = int(raw_weekday.strip())
        if weekday is None or weekday < 0 or weekday > 6:
            raise ScheduleError("weekday_range", label=label("weekday"))
    elif recurrence == "monthly":
        raw_monthday = values.get("monthday")
        monthday_token = normalize_token(raw_monthday)
        if raw_monthday in (None, ""):
            monthday = start_date.day
        elif monthday_token in ("ultimo", "ultima", "last"):
            monthday = -1
        elif isinstance(raw_monthday, bool):
            monthday = None
        else:
            try:
                monthday = int(raw_monthday)
            except (TypeError, ValueError):
                monthday = None
        if monthday not in {-1, *range(1, 32)}:
            raise ScheduleError("monthday_range", label=label("monthday"))

    if persisted:
        activity_id = values.get("id")
        if not valid_activity_id(activity_id):
            raise ScheduleError("saved_invalid_id")
    elif generate_id:
        activity_id = str(uuid.uuid4())
    else:
        raise ScheduleError("activity_id_required")

    item: dict[str, Any] = {
        "id": activity_id,
        "title": title,
        "weekday": weekday,
        "monthday": monthday,
        "startTime": start_time,
        "endTime": end_time,
        "recurrence": recurrence,
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat() if end_date else None,
        "location": bounded_text(values.get("location"), label("location"), 300),
        "notes": bounded_text(values.get("notes"), label("notes"), 4000),
        "links": normalize_links(values.get("links")),
    }
    if persisted and "sourceRow" in values:
        source_row = values["sourceRow"]
        if isinstance(source_row, bool) or not isinstance(source_row, int) or source_row < 1:
            raise ScheduleError("source_row")
        item["sourceRow"] = source_row
    return item


def stable_id(item: dict[str, Any], row_number: int) -> str:
    identity = {key: item[key] for key in sorted(item) if key not in ("id", "sourceRow")}
    payload = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(f"{row_number}:{payload}".encode("utf-8")).hexdigest()[:16]


def normalize_row(values: dict[str, str], row_number: int) -> dict[str, Any]:
    item = normalize_activity(
        {
            "title": values.get("title"),
            "weekday": values.get("weekday"),
            "monthday": values.get("monthday"),
            "startTime": values.get("start_time"),
            "endTime": values.get("end_time"),
            "recurrence": values.get("recurrence"),
            "startDate": values.get("start_date"),
            "endDate": values.get("end_date"),
            "location": values.get("location"),
            "notes": values.get("notes"),
            "links": [],
        },
        generate_id=True,
    )
    item["sourceRow"] = row_number
    item["id"] = stable_id(item, row_number)
    return item


def parse_csv(raw_path: str) -> dict[str, Any]:
    path = source_path(raw_path)
    text, encoding = read_csv_text(path)
    dialect = csv_dialect(text)
    reader = csv.DictReader(io.StringIO(text, newline=""), dialect=dialect)
    if not reader.fieldnames:
        raise ScheduleError("csv_no_header")

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
        errors.append(
            {
                "row": 1,
                "code": "missing_columns",
                "message": message("missing_columns", names=csv_field_names(missing)),
            }
        )
    if duplicate_fields:
        errors.append(
            {
                "row": 1,
                "code": "duplicate_columns",
                "message": message(
                    "duplicate_columns",
                    names=csv_field_names(sorted(set(duplicate_fields))),
                ),
            }
        )
    if unknown_headers:
        warnings.append(message("ignored_columns", names=", ".join(unknown_headers)))
    if encoding != "utf-8":
        warnings.append(message("latin1"))

    items: list[dict[str, Any]] = []
    if not errors:
        for row_number, raw_row in enumerate(reader, start=2):
            if row_number > MAX_ROWS + 1:
                errors.append(
                    {
                        "row": row_number,
                        "code": "row_limit",
                        "message": message("row_limit", limit=MAX_ROWS),
                    }
                )
                break
            if None in raw_row:
                errors.append(
                    {
                        "row": row_number,
                        "code": "extra_columns",
                        "message": message("extra_columns"),
                    }
                )
                continue
            if not any(
                str(raw_row.get(field) or "").strip()
                for field in (reader.fieldnames or [])
            ):
                continue
            values = {
                canonical: str(raw_row.get(original) or "").strip()
                for original, canonical in mapped_headers.items()
            }
            try:
                items.append(normalize_row(values, row_number))
            except ScheduleError as error:
                errors.append(error_issue(error, row_number))

    if not items and not errors:
        errors.append(
            {"row": 1, "code": "csv_empty", "message": message("csv_empty")}
        )

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
        raise ScheduleError("occurrence_window")

    occurrences: list[dict[str, Any]] = []
    current = start
    while current <= end and len(occurrences) < MAX_OCCURRENCES:
        for item in items:
            if occurs_on(item, current):
                activity_id = item["id"]
                notes = item.get("notes", item.get("description", ""))
                links = item.get("links", [])
                occurrences.append(
                    {
                        "id": (
                            f"{activity_id}:{current.isoformat()}:{item['startTime']}"
                        ),
                        "activityId": activity_id,
                        "scheduleId": activity_id,
                        "date": current.isoformat(),
                        "title": item["title"],
                        "startTime": item["startTime"],
                        "endTime": item["endTime"],
                        "recurrence": item["recurrence"],
                        "location": item.get("location", ""),
                        "notes": notes,
                        "links": links,
                        "description": notes,
                    }
                )
                if len(occurrences) >= MAX_OCCURRENCES:
                    break
        current += timedelta(days=1)

    occurrences.sort(key=lambda event: (event["date"], event["startTime"], event["title"].casefold()))
    return occurrences


def event_is_active(event: dict[str, Any], now: datetime) -> bool:
    return event_state(event, now) == "active"


def event_state(event: dict[str, Any], now: datetime) -> str:
    current = local_datetime(now)
    event_date = str(event.get("date") or "")
    today = current.date().isoformat()
    if event_date < today:
        return "occurred"
    if event_date > today:
        return "upcoming"
    try:
        start_hour, start_minute = (int(part) for part in event["startTime"].split(":"))
        end_hour, end_minute = (int(part) for part in event["endTime"].split(":"))
    except (KeyError, TypeError, ValueError):
        return "upcoming"
    current_minutes = current.hour * 60 + current.minute
    start_minutes = start_hour * 60 + start_minute
    end_minutes = end_hour * 60 + end_minute
    if current_minutes >= end_minutes:
        return "occurred"
    if current_minutes >= start_minutes:
        return "active"
    return "upcoming"


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
        raise ScheduleError("saved_start_time") from error


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
        "revision": 0,
        "title": DEFAULT_TITLE,
        "source": "",
        "sourceName": "",
        "importedAt": "",
        "items": [],
    }


def validate_store(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict) or payload.get("schemaVersion") != SCHEMA_VERSION:
        raise ScheduleError("store_unsupported")
    missing = STORE_FIELDS - set(payload)
    if missing:
        names = ", ".join(sorted(missing))
        raise ScheduleError("store_missing_fields", names=names)
    unknown = set(payload) - STORE_FIELDS
    if unknown:
        names = ", ".join(sorted(str(key) for key in unknown))
        raise ScheduleError("store_unknown_fields", names=names)

    revision = payload.get("revision")
    if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
        raise ScheduleError("store_invalid_revision")
    title = normalize_schedule_title(payload.get("title"))
    metadata: dict[str, str] = {}
    for field in ("source", "sourceName", "importedAt"):
        value = payload.get(field)
        if not isinstance(value, str):
            raise ScheduleError("store_invalid_metadata", field=field)
        metadata[field] = value
    if not isinstance(payload.get("items"), list):
        raise ScheduleError("store_invalid_activities")

    items: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for item in payload["items"]:
        normalized = normalize_activity(item, persisted=True)
        if normalized["id"] in seen_ids:
            raise ScheduleError("store_duplicate_ids")
        seen_ids.add(normalized["id"])
        items.append(normalized)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "revision": revision,
        "title": title,
        **metadata,
        "items": items,
    }


def migrate_v1_store(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1:
        raise ScheduleError("store_unsupported")
    old_items = payload.get("items")
    if not isinstance(old_items, list):
        raise ScheduleError("store_invalid_activities")

    items: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for old_item in old_items:
        if not isinstance(old_item, dict):
            raise ScheduleError("store_invalid_activities")
        activity_id = old_item.get("id")
        if not valid_activity_id(activity_id) or activity_id in seen_ids:
            activity_id = str(uuid.uuid4())
        candidate: dict[str, Any] = {
            "id": activity_id,
            "title": old_item.get("title"),
            "weekday": old_item.get("weekday"),
            "monthday": old_item.get("monthday"),
            "startTime": old_item.get("startTime"),
            "endTime": old_item.get("endTime"),
            "recurrence": old_item.get("recurrence"),
            "startDate": old_item.get("startDate"),
            "endDate": old_item.get("endDate"),
            "location": old_item.get("location"),
            "notes": old_item.get("notes", old_item.get("description", "")),
            "links": old_item.get("links", []),
        }
        if "sourceRow" in old_item:
            candidate["sourceRow"] = old_item["sourceRow"]
        normalized = normalize_activity(candidate, persisted=True)
        seen_ids.add(normalized["id"])
        items.append(normalized)

    old_title = payload.get("title")
    if not isinstance(old_title, str) or not old_title.strip():
        old_title = DEFAULT_TITLE
    migrated = {
        "schemaVersion": SCHEMA_VERSION,
        "revision": 0,
        "title": old_title,
        "source": str(payload.get("source") or ""),
        "sourceName": str(payload.get("sourceName") or ""),
        "importedAt": str(payload.get("importedAt") or ""),
        "items": items,
    }
    return validate_store(migrated)


def migration_backup_path(path: Path) -> Path:
    return path.with_name(path.name + ".v1.bak")


def write_migration_backup(path: Path, raw_payload: bytes) -> None:
    backup = migration_backup_path(path)
    try:
        fd = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw_payload)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        backup.unlink(missing_ok=True)
        raise


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


@contextmanager
def store_lock(path: Path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = path.with_name(path.name + ".lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def _load_store_unlocked(path: Path) -> dict[str, Any]:
    if not path.exists():
        return empty_store()
    try:
        raw_payload = path.read_bytes()
        payload = json.loads(raw_payload.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ScheduleError("store_read") from error
    if isinstance(payload, dict) and payload.get("schemaVersion") == 1:
        migrated = migrate_v1_store(payload)
        write_migration_backup(path, raw_payload)
        save_payload(migrated, path)
        return migrated
    return validate_store(payload)


def load_store(path: Path = STATE_FILE) -> dict[str, Any]:
    path = Path(path)
    with store_lock(path):
        return _load_store_unlocked(path)


def save_store(payload: dict[str, Any], path: Path = STATE_FILE) -> None:
    path = Path(path)
    normalized = validate_store(payload)
    with store_lock(path):
        save_payload(normalized, path)


def validate_expected_revision(expected_revision: Any) -> int:
    if (
        isinstance(expected_revision, bool)
        or not isinstance(expected_revision, int)
        or expected_revision < 0
    ):
        raise ScheduleError("expected_revision")
    return expected_revision


def _mutate_store(
    expected_revision: int,
    state_path: Path,
    mutation: Callable[[dict[str, Any]], None],
) -> dict[str, Any]:
    expected = validate_expected_revision(expected_revision)
    state_path = Path(state_path)
    with store_lock(state_path):
        current = _load_store_unlocked(state_path)
        if current["revision"] != expected:
            raise ScheduleError(
                "revision_conflict",
                code="revision_conflict",
                expected=expected,
                current=current["revision"],
            )
        updated = copy.deepcopy(current)
        mutation(updated)
        updated["revision"] = current["revision"] + 1
        updated = validate_store(updated)
        save_payload(updated, state_path)
        return status_payload(updated)


def rename_schedule(
    title: Any, expected_revision: int, state_path: Path = STATE_FILE
) -> dict[str, Any]:
    def rename(store: dict[str, Any]) -> None:
        store["title"] = normalize_schedule_title(title)

    return _mutate_store(expected_revision, state_path, rename)


def _copy_links_to_matching_titles(
    items: list[dict[str, Any]], source: dict[str, Any]
) -> int:
    title_key = source["title"].lower()
    updated_count = 0
    for index, candidate in enumerate(items):
        if candidate["title"].lower() != title_key:
            continue
        items[index] = normalize_activity(
            {**candidate, "links": copy.deepcopy(source["links"])}, persisted=True
        )
        updated_count += 1
    return updated_count


def create_activity(
    activity: dict[str, Any],
    expected_revision: int,
    state_path: Path = STATE_FILE,
    link_scope: str = "activity",
) -> dict[str, Any]:
    if link_scope not in ("activity", "same-title"):
        raise ScheduleError("link_scope")

    links_updated_count = 0

    def create(store: dict[str, Any]) -> None:
        nonlocal links_updated_count
        created_item = normalize_activity(activity, generate_id=True)
        store["items"].append(created_item)
        if link_scope == "activity":
            links_updated_count = 1
            return
        links_updated_count = _copy_links_to_matching_titles(
            store["items"], created_item
        )

    result = _mutate_store(expected_revision, state_path, create)
    result["linksUpdatedCount"] = links_updated_count
    result["linkScope"] = link_scope
    return result


def update_activity(
    activity_id: str,
    changes: dict[str, Any],
    expected_revision: int,
    state_path: Path = STATE_FILE,
    link_scope: str = "activity",
) -> dict[str, Any]:
    if link_scope not in ("activity", "same-title"):
        raise ScheduleError("link_scope")
    if link_scope == "same-title" and (
        not isinstance(changes, dict) or "links" not in changes
    ):
        raise ScheduleError("links_scope")

    links_updated_count = 0

    def update(store: dict[str, Any]) -> None:
        nonlocal links_updated_count
        if not isinstance(changes, dict):
            raise ScheduleError("changes_object")
        if "id" in changes:
            raise ScheduleError("id_edit")
        unknown = set(changes) - ACTIVITY_FIELDS
        if unknown:
            names = ", ".join(sorted(str(key) for key in unknown))
            raise ScheduleError("unknown_activity_fields", names=names)
        if not changes:
            raise ScheduleError("empty_changes")
        for index, item in enumerate(store["items"]):
            if item["id"] == activity_id:
                merged = {**item, **changes}
                updated_item = normalize_activity(merged, persisted=True)
                store["items"][index] = updated_item
                if "links" not in changes:
                    return
                if link_scope == "activity":
                    links_updated_count = 1
                    return
                links_updated_count = _copy_links_to_matching_titles(
                    store["items"], updated_item
                )
                return
        raise ScheduleError("activity_not_found", activity_id=activity_id)

    result = _mutate_store(expected_revision, state_path, update)
    result["linksUpdatedCount"] = links_updated_count
    result["linkScope"] = link_scope
    return result


def delete_activity(
    activity_id: str, expected_revision: int, state_path: Path = STATE_FILE
) -> dict[str, Any]:
    def delete(store: dict[str, Any]) -> None:
        for index, item in enumerate(store["items"]):
            if item["id"] == activity_id:
                del store["items"][index]
                return
        raise ScheduleError("activity_not_found", activity_id=activity_id)

    return _mutate_store(expected_revision, state_path, delete)


def clear_schedule(state_path: Path = STATE_FILE) -> dict[str, Any]:
    state_path = Path(state_path)
    with store_lock(state_path):
        current = _load_store_unlocked(state_path)
        cleared = empty_store()
        cleared["title"] = current["title"]
        cleared["revision"] = current["revision"] + 1
        save_payload(cleared, state_path)
        return status_payload(cleared)


def load_reminder_state(path: Path = REMINDER_STATE_FILE) -> dict[str, Any]:
    if not path.exists():
        return {"schemaVersion": 1, "sent": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ScheduleError("reminder_read") from error
    if (
        not isinstance(payload, dict)
        or payload.get("schemaVersion") != 1
        or not isinstance(payload.get("sent"), dict)
    ):
        raise ScheduleError("reminder_format")
    return payload


def clear_reminder_state(path: Path = REMINDER_STATE_FILE) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = path.with_suffix(path.suffix + ".lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path.unlink(missing_ok=True)


def send_class_notification(
    event: dict[str, Any], lead_minutes: int = REMINDER_LEAD_MINUTES
) -> None:
    omarchy = shutil.which("omarchy")
    if not omarchy:
        raise ScheduleError("notification_unavailable")
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
                message("notification_app"),
                "-u",
                "normal",
                "-i",
                "calendar",
                "-t",
                "10000",
                message(
                    "notification_one" if lead_minutes == 1 else "notification_other",
                    minutes=lead_minutes,
                ),
                details,
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ScheduleError("notification_failed", error=error) from error


def parse_reminder_identity(value: str) -> tuple[str, date, str | None] | None:
    current = re.fullmatch(r"(.+):(\d{4}-\d{2}-\d{2}):(\d{2}:\d{2})", value)
    legacy = re.fullmatch(r"(.+):(\d{4}-\d{2}-\d{2})", value)
    match = current or legacy
    if not match:
        return None
    try:
        occurrence_date = date.fromisoformat(match.group(2))
    except ValueError:
        return None
    return match.group(1), occurrence_date, match.group(3) if current else None


def _notify_due_classes_for_store(
    store: dict[str, Any],
    current: datetime,
    state_path: Path,
    notifier: Callable[[dict[str, Any], int], None],
) -> dict[str, Any]:
    state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = state_path.with_suffix(state_path.suffix + ".lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)

    with os.fdopen(lock_fd, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_reminder_state(state_path)
        sent = state["sent"]
        cutoff = current.date() - timedelta(days=REMINDER_RETENTION_DAYS)
        retained: dict[str, str] = {}
        live_start_times = {
            str(item.get("id")): str(item.get("startTime"))
            for item in store.get("items", [])
            if item.get("id") and item.get("startTime")
        }
        for occurrence_id, sent_at in sent.items():
            parsed = parse_reminder_identity(str(occurrence_id))
            if not parsed:
                continue
            activity_id, occurrence_date, start_time = parsed
            if activity_id not in live_start_times or occurrence_date < cutoff:
                continue
            normalized_id = str(occurrence_id)
            if start_time is None:
                normalized_id = (
                    f"{activity_id}:{occurrence_date.isoformat()}:"
                    f"{live_start_times[activity_id]}"
                )
            retained[normalized_id] = str(sent_at)

        notified: list[dict[str, Any]] = []
        errors: list[dict[str, Any]] = []
        for event in due_reminder_events(store.get("items", []), current):
            if event["id"] in retained:
                continue
            try:
                notifier(event, REMINDER_LEAD_MINUTES)
            except ScheduleError as error:
                errors.append(error_issue(error))
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


def notify_due_classes(
    store: dict[str, Any] | None = None,
    now: datetime | None = None,
    state_path: Path = REMINDER_STATE_FILE,
    notifier: Callable[[dict[str, Any], int], None] = send_class_notification,
    schedule_path: Path | None = None,
) -> dict[str, Any]:
    current = local_datetime(now or datetime.now())
    state_path = Path(state_path)
    if schedule_path is not None:
        schedule_path = Path(schedule_path)
        with store_lock(schedule_path):
            fresh_store = _load_store_unlocked(schedule_path)
            return _notify_due_classes_for_store(
                fresh_store, current, state_path, notifier
            )
    if store is None:
        raise ScheduleError("schedule_required")
    return _notify_due_classes_for_store(store, current, state_path, notifier)


def status_payload(
    store: dict[str, Any],
    today: date | None = None,
    days: int = 120,
    now: datetime | None = None,
) -> dict[str, Any]:
    reference_now = local_datetime(now or datetime.now())
    current = today or reference_now.date()
    if today is not None and now is None:
        reference_now = datetime.combine(today, reference_now.time())
    window_days = min(max(int(days), 1), 3660)
    week_start = current - timedelta(days=current.weekday())
    week_end = week_start + timedelta(days=6)
    range_end = max(week_end, current + timedelta(days=window_days))
    items = store.get("items", [])
    events = expand_occurrences(items, week_start, current - timedelta(days=1))
    events += expand_occurrences(items, current, range_end)
    events = events[:MAX_OCCURRENCES]
    for event in events:
        event["state"] = event_state(event, reference_now)
        event["active"] = event["state"] == "active"
    today_key = current.isoformat()
    active_events = [event for event in events if event["active"]]
    return {
        "ok": True,
        "schemaVersion": SCHEMA_VERSION,
        "revision": store.get("revision", 0),
        "title": store.get("title", DEFAULT_TITLE),
        "configured": bool(items),
        "source": store.get("source", ""),
        "sourceName": store.get("sourceName", ""),
        "importedAt": store.get("importedAt", ""),
        "items": items,
        "itemCount": len(items),
        "referenceDate": current.isoformat(),
        "weekStart": week_start.isoformat(),
        "weekEnd": week_end.isoformat(),
        "rangeStart": week_start.isoformat(),
        "rangeEnd": range_end.isoformat(),
        "todayCount": sum(1 for event in events if event["date"] == today_key),
        "activeCount": len(active_events),
        "activeTitle": active_events[0]["title"] if active_events else "",
        "events": events,
}


def import_csv(
    raw_path: str,
    state_path: Path = STATE_FILE,
    expected_revision: int | None = None,
) -> tuple[dict[str, Any], int]:
    preview = parse_csv(raw_path)
    if not preview["ok"]:
        return preview, 2
    state_path = Path(state_path)
    with store_lock(state_path):
        current = _load_store_unlocked(state_path)
        if expected_revision is not None:
            expected = validate_expected_revision(expected_revision)
            if current["revision"] != expected:
                raise ScheduleError(
                    "revision_conflict",
                    code="revision_conflict",
                    expected=expected,
                    current=current["revision"],
                )
        store = validate_store(
            {
                "schemaVersion": SCHEMA_VERSION,
                "revision": current["revision"] + 1,
                "title": current["title"],
                "source": preview["source"],
                "sourceName": preview["sourceName"],
                "importedAt": datetime.now(timezone.utc)
                .replace(microsecond=0)
                .isoformat(),
                "items": preview["items"],
            }
        )
        save_payload(store, state_path)
        result = status_payload(store)
        result["importedCount"] = len(store["items"])
        result["warnings"] = preview["warnings"]
        return result, 0


def print_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def read_json_stdin() -> dict[str, Any]:
    raw_payload = sys.stdin.readline(MAX_JSON_BYTES + 1)
    if len(raw_payload.encode("utf-8")) > MAX_JSON_BYTES:
        raise ScheduleError("json_too_large")
    try:
        payload = json.loads(raw_payload)
    except json.JSONDecodeError as error:
        raise ScheduleError("json_invalid") from error
    if not isinstance(payload, dict):
        raise ScheduleError("json_object")
    return payload


def validate_command_payload(
    payload: dict[str, Any], allowed: set[str], required: set[str]
) -> None:
    unknown = set(payload) - allowed
    if unknown:
        names = ", ".join(sorted(str(key) for key in unknown))
        raise ScheduleError("unknown_payload_fields", names=names)
    missing = required - set(payload)
    if missing:
        names = ", ".join(sorted(missing))
        raise ScheduleError("missing_payload_fields", names=names)


def requested_language(argv: list[str]) -> str:
    for index, argument in enumerate(argv):
        if argument.startswith("--language="):
            return set_language(argument.split("=", 1)[1])
        if argument == "--language" and index + 1 < len(argv):
            return set_language(argv[index + 1])
    return set_language("en")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=message("cli_description"))
    parser.add_argument(
        "--language",
        choices=("en", "es"),
        default=CURRENT_LANGUAGE,
        help=message("cli_language"),
    )
    commands = parser.add_subparsers(dest="command", required=True)
    preview = commands.add_parser("preview", help=message("cli_preview"))
    preview.add_argument("file")
    importer = commands.add_parser("import", help=message("cli_import"))
    importer.add_argument("file")
    importer.add_argument(
        "--expected-revision",
        type=int,
        help=message("cli_expected_revision"),
    )
    status = commands.add_parser("status", help=message("cli_status"))
    status.add_argument("--date", help=message("cli_date"))
    status.add_argument("--days", type=int, default=120)
    commands.add_parser(
        "rename-schedule",
        help=message("cli_rename"),
        description=message("cli_rename"),
    )
    commands.add_parser(
        "create-activity",
        help=message("cli_create"),
        description=message("cli_create"),
    )
    updater = commands.add_parser(
        "update-activity",
        help=message("cli_update"),
        description=message("cli_update"),
    )
    updater.add_argument("id")
    deleter = commands.add_parser(
        "delete-activity",
        help=message("cli_delete"),
        description=message("cli_delete"),
    )
    deleter.add_argument("id")
    commands.add_parser("choose", help=message("cli_choose"))
    commands.add_parser("remind", help=message("cli_remind"))
    commands.add_parser("clear", help=message("cli_clear"))
    return parser


def _main(argv: list[str] | None = None) -> int:
    raw_args = list(sys.argv[1:] if argv is None else argv)
    requested_language(raw_args)
    args = build_parser().parse_args(raw_args)
    set_language(args.language)
    try:
        if args.command == "preview":
            payload = parse_csv(args.file)
            print_json(payload)
            return 0 if payload["ok"] else 2
        if args.command == "import":
            payload, exit_code = import_csv(
                args.file, STATE_FILE, expected_revision=args.expected_revision
            )
            print_json(payload)
            return exit_code
        if args.command == "status":
            today = (
                parse_iso_date(args.date, message("field_date"))
                if args.date
                else date.today()
            )
            print_json(status_payload(load_store(STATE_FILE), today=today, days=args.days))
            return 0
        if args.command == "rename-schedule":
            request = read_json_stdin()
            validate_command_payload(
                request,
                {"expectedRevision", "title"},
                {"expectedRevision", "title"},
            )
            print_json(
                rename_schedule(
                    request["title"], request["expectedRevision"], STATE_FILE
                )
            )
            return 0
        if args.command == "create-activity":
            request = read_json_stdin()
            validate_command_payload(
                request,
                {"expectedRevision", "activity", "linkScope"},
                {"expectedRevision", "activity"},
            )
            print_json(
                create_activity(
                    request["activity"],
                    request["expectedRevision"],
                    STATE_FILE,
                    link_scope=request.get("linkScope", "activity"),
                )
            )
            return 0
        if args.command == "update-activity":
            request = read_json_stdin()
            validate_command_payload(
                request,
                {"expectedRevision", "changes", "linkScope"},
                {"expectedRevision", "changes"},
            )
            print_json(
                update_activity(
                    args.id,
                    request["changes"],
                    request["expectedRevision"],
                    STATE_FILE,
                    link_scope=request.get("linkScope", "activity"),
                )
            )
            return 0
        if args.command == "delete-activity":
            request = read_json_stdin()
            validate_command_payload(
                request, {"expectedRevision"}, {"expectedRevision"}
            )
            print_json(
                delete_activity(args.id, request["expectedRevision"], STATE_FILE)
            )
            return 0
        if args.command == "choose":
            payload = choose_csv()
            print_json(payload)
            return 0
        if args.command == "remind":
            payload = notify_due_classes(
                state_path=REMINDER_STATE_FILE, schedule_path=STATE_FILE
            )
            print_json(payload)
            return 0 if payload["ok"] else 2
        if args.command == "clear":
            payload = clear_schedule(STATE_FILE)
            clear_reminder_state(REMINDER_STATE_FILE)
            print_json(payload)
            return 0
    except ScheduleError as error:
        print_json({"ok": False, "errors": [error_issue(error)]})
        return 2
    except OSError as error:
        print_json(
            {
                "ok": False,
                "errors": [
                    {
                        "row": 0,
                        "code": "file_operation",
                        "message": message("file_operation", error=error),
                    }
                ],
            }
        )
        return 2
    return 1


def main(argv: list[str] | None = None) -> int:
    previous_language = CURRENT_LANGUAGE
    try:
        return _main(argv)
    finally:
        set_language(previous_language)


if __name__ == "__main__":
    sys.exit(main())
