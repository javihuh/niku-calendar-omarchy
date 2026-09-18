import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
import uuid
from contextlib import redirect_stdout
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

    def activity(self, **changes):
        activity = {
            "title": "Programacion",
            "weekday": 1,
            "monthday": None,
            "startTime": "10:00",
            "endTime": "11:30",
            "recurrence": "weekly",
            "startDate": "2026-09-15",
            "endDate": None,
            "location": "Laboratorio 2",
            "notes": "Practica",
            "links": [],
        }
        activity.update(changes)
        return activity

    def test_manifest_declares_english_default_and_spanish_option(self):
        manifest = json.loads((MODULE_PATH.parent / "manifest.json").read_text())
        widget = manifest["barWidget"]
        language = next(
            entry for entry in widget["schema"] if entry["key"] == "language"
        )

        self.assertEqual(widget["defaults"]["language"], "English")
        self.assertEqual(language["defaultValue"], "English")
        self.assertEqual(language["options"], ["English", "Español"])

    def test_backend_translation_catalogs_have_matching_keys_and_placeholders(self):
        english = schedule.BACKEND_MESSAGES["en"]
        spanish = schedule.BACKEND_MESSAGES["es"]

        self.assertEqual(set(english), set(spanish))
        for key in english:
            with self.subTest(key=key):
                english_fields = sorted(
                    part.split("}", 1)[0] for part in english[key].split("{")[1:]
                )
                spanish_fields = sorted(
                    part.split("}", 1)[0] for part in spanish[key].split("{")[1:]
                )
                self.assertEqual(english_fields, spanish_fields)

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

    def test_rejects_unquoted_delimiters_that_add_csv_values(self):
        for notes in ("Nota sin,comillas", "Nota,"):
            with self.subTest(notes=notes), tempfile.TemporaryDirectory() as directory:
                path = self.write_csv(
                    directory,
                    "Clase,martes,,08:00,09:00,semanal,2026-09-15,,Aula,"
                    + notes
                    + "\n",
                )
                result = schedule.parse_csv(str(path))

            self.assertFalse(result["ok"])
            self.assertEqual(result["validCount"], 0)
            self.assertEqual(result["errors"][0]["row"], 2)
            self.assertEqual(result["errors"][0]["code"], "extra_columns")

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
        self.assertIn("Activity in 5 minutes", command)
        self.assertIn("Programacion\n10:00 - 11:30 | Laboratorio 2", command)

        try:
            schedule.set_language("es")
            with mock.patch.object(
                schedule.shutil, "which", return_value="/usr/bin/omarchy"
            ), mock.patch.object(schedule.subprocess, "run") as spanish_run:
                schedule.send_class_notification(event)
            spanish_command = spanish_run.call_args.args[0]
            self.assertIn("Actividad en 5 minutos", spanish_command)
            self.assertIn("Horario recurrente", spanish_command)
        finally:
            schedule.set_language("en")

    def test_invalid_end_time_is_reported_with_row(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_csv(
                directory,
                "Clase,lunes,,10:00,09:00,semanal,2026-09-21,,,\n",
            )
            result = schedule.parse_csv(str(path))

        self.assertFalse(result["ok"])
        self.assertEqual(result["errors"][0]["row"], 2)
        self.assertEqual(result["errors"][0]["code"], "end_later")
        self.assertIn("end time", result["errors"][0]["message"])

    def test_spanish_language_localizes_errors_without_changing_csv_data(self):
        with tempfile.TemporaryDirectory() as directory:
            invalid_path = self.write_csv(
                directory,
                "Clase,lunes,,10:00,09:00,semanal,2026-09-21,,,\n",
            )
            try:
                schedule.set_language("es")
                invalid = schedule.parse_csv(str(invalid_path))
                valid_path = self.write_csv(
                    directory,
                    "Clase,lunes,,10:00,11:00,semanal,2026-09-21,,,\n",
                )
                spanish = schedule.parse_csv(str(valid_path))
                schedule.set_language("en")
                english = schedule.parse_csv(str(valid_path))
            finally:
                schedule.set_language("en")

        self.assertEqual(invalid["errors"][0]["code"], "end_later")
        self.assertIn("la hora de fin", invalid["errors"][0]["message"])
        self.assertEqual(spanish["items"], english["items"])

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

    def test_migrates_v1_once_with_backup_and_preserves_activities(self):
        first = self.activity()
        first.update({"id": "existing-id", "description": "Nota antigua"})
        first.pop("notes")
        first.pop("links")
        second = dict(first)
        second.update({"id": "", "title": "Fisica", "description": "Otra nota"})
        v1 = {
            "schemaVersion": 1,
            "source": "/tmp/horario.csv",
            "sourceName": "horario.csv",
            "importedAt": "2026-09-15T00:00:00+00:00",
            "items": [first, second],
        }

        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state" / "schedule.json"
            state_path.parent.mkdir()
            original = (json.dumps(v1, ensure_ascii=False) + "\n").encode("utf-8")
            state_path.write_bytes(original)

            migrated = schedule.load_store(state_path)
            backup_path = schedule.migration_backup_path(state_path)
            first_backup = backup_path.read_bytes()
            loaded_again = schedule.load_store(state_path)

        self.assertEqual(migrated, loaded_again)
        self.assertEqual(first_backup, original)
        self.assertEqual(migrated["schemaVersion"], 2)
        self.assertEqual(migrated["revision"], 0)
        self.assertEqual(migrated["title"], "Schedule")
        self.assertEqual(len(migrated["items"]), 2)
        self.assertEqual(migrated["items"][0]["id"], "existing-id")
        self.assertEqual(migrated["items"][0]["notes"], "Nota antigua")
        self.assertEqual(migrated["items"][0]["links"], [])
        self.assertNotIn("description", migrated["items"][0])
        uuid.UUID(migrated["items"][1]["id"])
        self.assertEqual(set(migrated), schedule.STORE_FIELDS)

    def test_crud_preserves_id_and_returns_complete_status(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            renamed = schedule.rename_schedule("Mi horario", 0, state_path)
            created = schedule.create_activity(self.activity(), 1, state_path)
            activity_id = created["items"][0]["id"]
            uuid.UUID(activity_id)
            updated = schedule.update_activity(
                activity_id,
                {
                    "title": "Programacion avanzada",
                    "notes": "Tema nuevo",
                    "links": [
                        {
                            "label": "Material",
                            "url": "HTTPS://Example.COM:443/tema uno",
                        }
                    ],
                },
                2,
                state_path,
            )
            stored_after_update = schedule.load_store(state_path)
            deleted = schedule.delete_activity(activity_id, 3, state_path)

        self.assertEqual(renamed["title"], "Mi horario")
        self.assertEqual(renamed["revision"], 1)
        self.assertEqual(created["revision"], 2)
        self.assertIn("events", created)
        self.assertEqual(updated["revision"], 3)
        self.assertEqual(updated["items"][0]["id"], activity_id)
        self.assertEqual(
            updated["items"][0]["links"][0]["url"],
            "https://example.com/tema%20uno",
        )
        self.assertEqual(stored_after_update["title"], "Mi horario")
        self.assertEqual(deleted["revision"], 4)
        self.assertEqual(deleted["items"], [])

    def test_expanded_event_exposes_activity_notes_and_links(self):
        item = schedule.normalize_activity(
            {
                "id": "class-one",
                **self.activity(
                    recurrence="once",
                    weekday=None,
                    startDate="2026-09-15",
                    endDate=None,
                    links=[{"label": "Aula", "url": "https://example.com/aula"}],
                ),
            },
            persisted=True,
        )
        event = schedule.expand_occurrences(
            [item], date(2026, 9, 15), date(2026, 9, 15)
        )[0]

        self.assertEqual(event["activityId"], "class-one")
        self.assertEqual(event["scheduleId"], "class-one")
        self.assertEqual(event["notes"], "Practica")
        self.assertEqual(event["links"][0]["label"], "Aula")
        self.assertTrue(event["id"].endswith(":2026-09-15:10:00"))

    def test_links_can_apply_to_one_activity_or_every_matching_title(self):
        shared_links = [{"label": "Campus", "url": "https://example.com/campus"}]
        alternate_links = [
            {"label": "Clase especial", "url": "https://example.com/especial"}
        ]

        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            first = schedule.create_activity(self.activity(), 0, state_path)
            first_id = first["items"][0]["id"]
            second = schedule.create_activity(
                self.activity(
                    title="programacion",
                    weekday=2,
                    startTime="12:00",
                    endTime="13:30",
                ),
                1,
                state_path,
            )
            second_id = second["items"][1]["id"]
            third = schedule.create_activity(
                self.activity(title="Fisica", weekday=3), 2, state_path
            )
            third_id = third["items"][2]["id"]

            shared = schedule.update_activity(
                first_id,
                {"notes": "Solo esta actividad", "links": shared_links},
                3,
                state_path,
                link_scope="same-title",
            )
            separate = schedule.update_activity(
                second_id,
                {"links": alternate_links},
                4,
                state_path,
                link_scope="activity",
            )

        shared_by_id = {item["id"]: item for item in shared["items"]}
        separate_by_id = {item["id"]: item for item in separate["items"]}
        self.assertEqual(shared["linksUpdatedCount"], 2)
        self.assertEqual(shared_by_id[first_id]["links"], shared_links)
        self.assertEqual(shared_by_id[second_id]["links"], shared_links)
        self.assertEqual(shared_by_id[third_id]["links"], [])
        self.assertEqual(shared_by_id[first_id]["notes"], "Solo esta actividad")
        self.assertEqual(shared_by_id[second_id]["notes"], "Practica")
        self.assertEqual(separate["linksUpdatedCount"], 1)
        self.assertEqual(separate_by_id[first_id]["links"], shared_links)
        self.assertEqual(separate_by_id[second_id]["links"], alternate_links)

    def test_create_can_apply_links_to_every_matching_title(self):
        shared_links = [{"label": "Meet", "url": "https://example.com/meet"}]

        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            first = schedule.create_activity(self.activity(), 0, state_path)
            first_id = first["items"][0]["id"]
            created = schedule.create_activity(
                self.activity(
                    title="programacion",
                    weekday=4,
                    links=shared_links,
                ),
                1,
                state_path,
                link_scope="same-title",
            )

        created_by_id = {item["id"]: item for item in created["items"]}
        self.assertEqual(created["revision"], 2)
        self.assertEqual(created["linksUpdatedCount"], 2)
        self.assertEqual(created_by_id[first_id]["links"], shared_links)
        self.assertEqual(created["items"][1]["links"], shared_links)

    def test_rejects_immutable_and_unknown_activity_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            with self.assertRaisesRegex(schedule.ScheduleError, "immutable"):
                schedule.create_activity(
                    {**self.activity(), "id": "chosen"}, 0, state_path
                )
            created = schedule.create_activity(self.activity(), 0, state_path)
            activity_id = created["items"][0]["id"]
            with self.assertRaisesRegex(schedule.ScheduleError, "immutable"):
                schedule.update_activity(
                    activity_id, {"id": "replacement"}, 1, state_path
                )
            with self.assertRaisesRegex(schedule.ScheduleError, "Unknown activity"):
                schedule.update_activity(
                    activity_id, {"color": "blue"}, 1, state_path
                )
            with self.assertRaisesRegex(schedule.ScheduleError, "linkScope"):
                schedule.update_activity(
                    activity_id,
                    {"links": []},
                    1,
                    state_path,
                    link_scope="everything",
                )
            stored = schedule.load_store(state_path)

        self.assertEqual(stored["revision"], 1)
        self.assertEqual(stored["items"][0]["id"], activity_id)

    def test_rejects_invalid_text_bounds_and_links(self):
        invalid_activities = [
            self.activity(title=""),
            self.activity(title="x" * 201),
            self.activity(location="x" * 301),
            self.activity(notes="x" * 4001),
            self.activity(links=[{"label": "", "url": "https://example.com"}]),
            self.activity(links=[{"label": "Web", "url": "ftp://example.com"}]),
            self.activity(links=[{"label": "Web", "url": "https://user:pass@example.com"}]),
            self.activity(links=[{"label": "Web", "url": "https://example.com/\n"}]),
            self.activity(links=[{"label": "Web", "url": "https:///missing-host"}]),
            self.activity(
                links=[{"label": str(index), "url": "https://example.com"} for index in range(11)]
            ),
        ]

        for activity in invalid_activities:
            with self.subTest(activity=activity):
                with self.assertRaises(schedule.ScheduleError):
                    schedule.normalize_activity(activity, generate_id=True)

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(schedule.ScheduleError):
                schedule.rename_schedule("", 0, Path(directory) / "schedule.json")
            with self.assertRaises(schedule.ScheduleError):
                schedule.rename_schedule(
                    "x" * 201, 0, Path(directory) / "schedule.json"
                )

    def test_revision_conflict_does_not_overwrite_newer_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            first = schedule.create_activity(self.activity(), 0, state_path)
            with self.assertRaisesRegex(schedule.ScheduleError, "Revision conflict"):
                schedule.create_activity(
                    self.activity(title="Fisica"), 0, state_path
                )
            stored = schedule.load_store(state_path)

        self.assertEqual(first["revision"], 1)
        self.assertEqual(stored["revision"], 1)
        self.assertEqual([item["title"] for item in stored["items"]], ["Programacion"])

    def test_csv_import_replaces_items_preserves_title_and_increments_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "schedule.json"
            schedule.rename_schedule("Universidad", 0, state_path)
            created = schedule.create_activity(self.activity(), 1, state_path)
            old_id = created["items"][0]["id"]
            csv_path = self.write_csv(
                directory,
                "Fisica,martes,,08:00,09:00,semanal,2026-09-15,,Aula,Formula\n",
            )

            imported, exit_code = schedule.import_csv(
                str(csv_path), state_path, expected_revision=2
            )
            imported_again, second_exit = schedule.import_csv(
                str(csv_path), state_path, expected_revision=3
            )

        self.assertEqual(exit_code, 0)
        self.assertEqual(second_exit, 0)
        self.assertEqual(imported["title"], "Universidad")
        self.assertEqual(imported["revision"], 3)
        self.assertEqual(imported["itemCount"], 1)
        self.assertEqual(imported["items"][0]["notes"], "Formula")
        self.assertNotEqual(imported["items"][0]["id"], old_id)
        self.assertEqual(imported_again["title"], "Universidad")
        self.assertEqual(imported_again["revision"], 4)
        self.assertEqual(
            imported_again["items"][0]["id"], imported["items"][0]["id"]
        )

    def test_reminder_identity_survives_content_edit_changes_on_time_edit_and_prunes_delete(self):
        item = {"id": "class-one", **self.activity()}
        notifier = mock.Mock()
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "reminders.json"
            first = schedule.notify_due_classes(
                {"items": [item]},
                now=datetime(2026, 9, 15, 9, 55),
                state_path=state_path,
                notifier=notifier,
            )
            content_edit = {
                **item,
                "title": "Programacion avanzada",
                "notes": "Notas cambiadas",
                "links": [{"label": "Web", "url": "https://example.com"}],
            }
            unchanged = schedule.notify_due_classes(
                {"items": [content_edit]},
                now=datetime(2026, 9, 15, 9, 57),
                state_path=state_path,
                notifier=notifier,
            )
            time_edit = {**content_edit, "startTime": "10:02"}
            moved = schedule.notify_due_classes(
                {"items": [time_edit]},
                now=datetime(2026, 9, 15, 9, 57),
                state_path=state_path,
                notifier=notifier,
            )
            deleted = schedule.notify_due_classes(
                {"items": []},
                now=datetime(2026, 9, 15, 9, 58),
                state_path=state_path,
                notifier=notifier,
            )
            reminder_state = schedule.load_reminder_state(state_path)

        self.assertEqual(first["notifiedCount"], 1)
        self.assertEqual(unchanged["notifiedCount"], 0)
        self.assertEqual(moved["notifiedCount"], 1)
        self.assertEqual(deleted["notifiedCount"], 0)
        self.assertEqual(notifier.call_count, 2)
        self.assertEqual(reminder_state["sent"], {})

    def test_cli_mutation_reads_json_from_stdin_and_reports_conflict_as_json(self):
        request = {
            "expectedRevision": 0,
            "activity": self.activity(recurrence="once", weekday=None),
            "linkScope": "same-title",
        }
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            schedule, "STATE_FILE", Path(directory) / "schedule.json"
        ):
            output = io.StringIO()
            with mock.patch.object(
                schedule.sys, "stdin", io.StringIO(json.dumps(request))
            ), redirect_stdout(output):
                exit_code = schedule.main(["create-activity"])
            created = json.loads(output.getvalue())

            conflict_output = io.StringIO()
            with mock.patch.object(
                schedule.sys, "stdin", io.StringIO(json.dumps(request))
            ), redirect_stdout(conflict_output):
                conflict_code = schedule.main(["create-activity"])
            conflict = json.loads(conflict_output.getvalue())

        self.assertEqual(exit_code, 0)
        self.assertEqual(created["revision"], 1)
        self.assertEqual(created["linkScope"], "same-title")
        self.assertEqual(created["linksUpdatedCount"], 1)
        self.assertIn("items", created)
        self.assertIn("events", created)
        self.assertEqual(conflict_code, 2)
        self.assertFalse(conflict["ok"])
        self.assertEqual(conflict["errors"][0]["code"], "revision_conflict")
        self.assertIn("Revision conflict", conflict["errors"][0]["message"])

    def test_cli_can_return_spanish_errors(self):
        request = {
            "expectedRevision": 0,
            "activity": self.activity(recurrence="once", weekday=None),
        }
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            schedule, "STATE_FILE", Path(directory) / "schedule.json"
        ):
            with mock.patch.object(
                schedule.sys, "stdin", io.StringIO(json.dumps(request))
            ), redirect_stdout(io.StringIO()):
                schedule.main(["create-activity"])

            output = io.StringIO()
            with mock.patch.object(
                schedule.sys, "stdin", io.StringIO(json.dumps(request))
            ), redirect_stdout(output):
                exit_code = schedule.main(
                    ["--language", "es", "create-activity"]
                )
            result = json.loads(output.getvalue())

        schedule.set_language("en")
        self.assertEqual(exit_code, 2)
        self.assertEqual(result["errors"][0]["code"], "revision_conflict")
        self.assertIn("Conflicto de revisión", result["errors"][0]["message"])

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
