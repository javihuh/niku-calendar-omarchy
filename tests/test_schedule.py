import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "schedule.py"
SPEC = importlib.util.spec_from_file_location("recurring_schedule", MODULE_PATH)
schedule = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(schedule)


HEADER = (
    "titulo,dia_semana,dia_mes,hora_inicio,hora_fin,repeticion,"
    "desde,hasta,ubicacion,descripcion\n"
)


class ScheduleTests(unittest.TestCase):
    def write_csv(self, directory, body, header=HEADER):
        path = Path(directory) / "horario.csv"
        path.write_text(header + body, encoding="utf-8")
        return path

    def test_parses_spanish_weekly_activity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_csv(
                directory,
                "Matematicas,lunes,,08:00,09:30,semanal,2026-09-21,2026-12-18,Aula 3,Clase\n",
            )
            result = schedule.parse_csv(str(path))

        self.assertTrue(result["ok"])
        self.assertEqual(result["validCount"], 1)
        self.assertEqual(result["items"][0]["recurrence"], "weekly")
        self.assertEqual(result["items"][0]["weekday"], 0)

    def test_detects_semicolon_delimiter_and_accents(self):
        header = HEADER.replace(",", ";")
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_csv(
                directory,
                "Gimnasio;miércoles;;18:00;19:30;semanal;2026-09-23;;;\n",
                header=header,
            )
            result = schedule.parse_csv(str(path))

        self.assertTrue(result["ok"])
        self.assertEqual(result["delimiter"], ";")
        self.assertEqual(result["items"][0]["weekday"], 2)

    def test_biweekly_uses_start_week_as_anchor(self):
        item = {
            "id": "shift",
            "title": "Turno",
            "weekday": 3,
            "monthday": None,
            "startTime": "09:00",
            "endTime": "10:00",
            "recurrence": "biweekly",
            "startDate": "2026-09-15",
            "endDate": None,
            "location": "",
            "description": "",
        }
        events = schedule.expand_occurrences(
            [item], date(2026, 9, 15), date(2026, 10, 2)
        )
        self.assertEqual(
            [event["date"] for event in events],
            ["2026-09-17", "2026-10-01"],
        )

    def test_biweekly_starts_on_next_valid_weekday(self):
        item = {
            "id": "shift",
            "title": "Turno",
            "weekday": 0,
            "monthday": None,
            "startTime": "09:00",
            "endTime": "10:00",
            "recurrence": "biweekly",
            "startDate": "2026-09-15",
            "endDate": None,
            "location": "",
            "description": "",
        }
        events = schedule.expand_occurrences(
            [item], date(2026, 9, 15), date(2026, 10, 12)
        )
        self.assertEqual(
            [event["date"] for event in events],
            ["2026-09-21", "2026-10-05"],
        )

    def test_monthly_day_31_skips_short_months(self):
        item = {
            "id": "close",
            "title": "Cierre",
            "weekday": None,
            "monthday": 31,
            "startTime": "17:00",
            "endTime": "18:00",
            "recurrence": "monthly",
            "startDate": "2026-01-31",
            "endDate": None,
            "location": "",
            "description": "",
        }
        events = schedule.expand_occurrences(
            [item], date(2026, 1, 1), date(2026, 3, 31)
        )
        self.assertEqual(
            [event["date"] for event in events],
            ["2026-01-31", "2026-03-31"],
        )

    def test_last_day_tracks_each_month(self):
        item = {
            "id": "payroll",
            "title": "Nomina",
            "weekday": None,
            "monthday": -1,
            "startTime": "09:00",
            "endTime": "09:15",
            "recurrence": "monthly",
            "startDate": "2026-01-01",
            "endDate": None,
            "location": "",
            "description": "",
        }
        events = schedule.expand_occurrences(
            [item], date(2026, 1, 1), date(2026, 3, 31)
        )
        self.assertEqual(
            [event["date"] for event in events],
            ["2026-01-31", "2026-02-28", "2026-03-31"],
        )

    def test_status_marks_only_current_class_active(self):
        store = {
            "schemaVersion": 1,
            "source": "horario.csv",
            "sourceName": "horario.csv",
            "importedAt": "2026-09-15T00:00:00+00:00",
            "items": [
                {
                    "id": "class-one",
                    "title": "Programacion",
                    "weekday": 1,
                    "monthday": None,
                    "startTime": "09:00",
                    "endTime": "10:30",
                    "recurrence": "weekly",
                    "startDate": "2026-09-15",
                    "endDate": None,
                    "location": "Laboratorio 2",
                    "description": "",
                },
                {
                    "id": "class-two",
                    "title": "Fisica",
                    "weekday": 1,
                    "monthday": None,
                    "startTime": "11:00",
                    "endTime": "12:30",
                    "recurrence": "weekly",
                    "startDate": "2026-09-15",
                    "endDate": None,
                    "location": "Aula B204",
                    "description": "",
                },
            ],
        }
        status = schedule.status_payload(
            store,
            days=1,
            now=datetime(2026, 9, 15, 9, 45),
        )

        self.assertEqual(status["activeCount"], 1)
        self.assertEqual(status["activeTitle"], "Programacion")
        self.assertTrue(status["events"][0]["active"])
        self.assertFalse(status["events"][1]["active"])

    def test_class_is_inactive_at_exact_end_time(self):
        event = {
            "date": "2026-09-15",
            "startTime": "09:00",
            "endTime": "10:30",
        }
        self.assertFalse(
            schedule.event_is_active(event, datetime(2026, 9, 15, 10, 30))
        )

    def test_reminder_is_sent_once_five_minutes_before_class(self):
        store = {
            "items": [
                {
                    "id": "class-one",
                    "title": "Programacion",
                    "weekday": 1,
                    "monthday": None,
                    "startTime": "10:00",
                    "endTime": "11:30",
                    "recurrence": "weekly",
                    "startDate": "2026-09-15",
                    "endDate": None,
                    "location": "Laboratorio 2",
                    "description": "",
                }
            ]
        }
        notifier = mock.Mock()
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "reminders.json"
            first = schedule.notify_due_classes(
                store,
                now=datetime(2026, 9, 15, 9, 55),
                state_path=state_path,
                notifier=notifier,
            )
            second = schedule.notify_due_classes(
                store,
                now=datetime(2026, 9, 15, 9, 57),
                state_path=state_path,
                notifier=notifier,
            )

        self.assertEqual(first["notifiedCount"], 1)
        self.assertEqual(second["notifiedCount"], 0)
        notifier.assert_called_once()

    def test_reminder_window_excludes_early_and_started_classes(self):
        item = {
            "id": "class-one",
            "title": "Programacion",
            "weekday": 1,
            "monthday": None,
            "startTime": "10:00",
            "endTime": "11:30",
            "recurrence": "weekly",
            "startDate": "2026-09-15",
            "endDate": None,
            "location": "",
            "description": "",
        }

        self.assertEqual(
            schedule.due_reminder_events(
                [item], datetime(2026, 9, 15, 9, 54, 59)
            ),
            [],
        )
        self.assertEqual(
            schedule.due_reminder_events([item], datetime(2026, 9, 15, 10, 0)),
            [],
        )

    def test_notification_uses_omarchy_and_includes_class_details(self):
        event = {
            "title": "Programacion",
            "startTime": "10:00",
            "endTime": "11:30",
            "location": "Laboratorio 2",
        }
        with mock.patch.object(
            schedule.shutil, "which", return_value="/usr/bin/omarchy"
        ), mock.patch.object(schedule.subprocess, "run") as run:
            schedule.send_class_notification(event)

        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["/usr/bin/omarchy", "notification", "send"])
        self.assertIn("Clase en 5 minutos", command)
        self.assertIn("Programacion\n10:00 - 11:30 | Laboratorio 2", command)

    def test_invalid_end_time_is_reported_with_row(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_csv(
                directory,
                "Clase,lunes,,10:00,09:00,semanal,2026-09-21,,,,\n",
            )
            result = schedule.parse_csv(str(path))

        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["row"], 2)
        self.assertIn("hora_fin", result["errors"][0]["message"])

    def test_import_replaces_store_and_builds_status(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_csv(
                directory,
                "Clase,martes,,08:00,09:00,semanal,2026-09-15,,Aula,\n",
            )
            state_path = Path(directory) / "state" / "schedule.json"
            imported, exit_code = schedule.import_csv(str(path), state_path)
            stored = json.loads(state_path.read_text(encoding="utf-8"))
            status = schedule.status_payload(stored, today=date(2026, 9, 15), days=7)

        self.assertEqual(exit_code, 0)
        self.assertEqual(imported["importedCount"], 1)
        self.assertEqual(status["todayCount"], 1)
        self.assertEqual(status["events"][0]["title"], "Clase")

    def test_external_chooser_returns_selected_csv(self):
        with tempfile.TemporaryDirectory() as directory:
            csv_path = self.write_csv(
                directory,
                "Clase,martes,,08:00,09:00,semanal,2026-09-15,,Aula,\n",
            )

            def select_file(command, **kwargs):
                chooser_arg = next(part for part in command if part.startswith("--chooser-file="))
                Path(chooser_arg.split("=", 1)[1]).write_text(str(csv_path) + "\n", encoding="utf-8")
                return subprocess.CompletedProcess(command, 0)

            with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}), mock.patch.object(
                schedule.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}"
            ), mock.patch.object(schedule.subprocess, "run", side_effect=select_file):
                result = schedule.choose_csv()

        self.assertTrue(result["ok"])
        self.assertEqual(result["path"], str(csv_path.resolve()))

    def test_external_chooser_can_be_cancelled(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(
            os.environ, {"XDG_RUNTIME_DIR": directory}
        ), mock.patch.object(
            schedule.shutil, "which", side_effect=lambda name: f"/usr/bin/{name}"
        ), mock.patch.object(
            schedule.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0),
        ):
            result = schedule.choose_csv()

        self.assertFalse(result["ok"])
        self.assertTrue(result["cancelled"])


if __name__ == "__main__":
    unittest.main()
