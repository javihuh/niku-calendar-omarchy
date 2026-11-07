"""Canvas integration tests with no network or real credentials."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import canvas


class Response:
    def __init__(self, items, link=""):
        self.items = items
        self.headers = {"Link": link}

    def read(self, *args):
        return json.dumps(self.items).encode()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


class CanvasTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.config = root / "canvas.json"
        self.cache = root / "cache.json"
        token = root / "token"
        token.write_text("example-token")
        token.chmod(0o600)
        self.config.write_text(json.dumps({"baseUrl": "https://canvas.example.edu", "tokenFile": str(token)}))

    def test_normalize_filters_completed_and_keeps_user_due_date(self):
        result = canvas.normalize([{"id": 10, "name": "Math"}], [
            {"plannable_type": "assignment", "plannable_id": 7, "course_id": 10,
             "plannable": {"name": "Report", "due_at": "2026-10-07T23:59:00Z"},
             "html_url": "/courses/10/assignments/7", "submissions": False},
            {"plannable_type": "assignment", "plannable_id": 8, "course_id": 10,
             "plannable": {"name": "Done", "due_at": "2026-10-08T23:59:00Z"},
             "planner_override": {"marked_complete": True}},
        ], "https://canvas.example.edu")
        self.assertEqual([a["done"] for a in result["assignments"]], [False, True])
        self.assertEqual(result["assignments"][0]["course"], "Math")

    def test_cache_survives_outage_and_skips_recent_fetch(self):
        def opener(request, timeout):
            self.assertEqual(request.get_header("Authorization"), "Bearer example-token")
            if "/courses?" in request.full_url:
                return Response([{"id": 10, "name": "Math"}])
            return Response([{"plannable_type": "assignment", "course_id": 10,
                              "plannable_id": 7, "plannable": {"name": "Report", "due_at": "2026-10-07T23:59:00Z"}}])

        first = canvas.status(self.config, self.cache, now=1000, opener=opener)
        self.assertEqual(len(first["assignments"]), 1)
        self.assertEqual(self.cache.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("example-token", self.cache.read_text())
        recent = canvas.status(self.config, self.cache, now=1001,
                               opener=lambda *args, **kwargs: self.fail("unnecessary request"))
        self.assertFalse(recent["stale"])
        offline = canvas.status(self.config, self.cache, now=2000,
                                opener=lambda *args, **kwargs: (_ for _ in ()).throw(OSError("offline")))
        self.assertTrue(offline["stale"])
        self.assertEqual(first["assignments"], offline["assignments"])

    def test_unconfigured_does_not_use_previous_cache(self):
        result = canvas.status(Path(self.temp.name) / "missing", self.cache)
        self.assertFalse(result["configured"])
        self.assertEqual(result["assignments"], [])

    def test_follows_same_origin_pagination_only(self):
        def opener(request, timeout):
            if "page=2" in request.full_url:
                return Response([{"id": 2}])
            return Response([{"id": 1}],
                            '<https://canvas.example.edu/api/v1/courses?page=2>; rel="next"')

        self.assertEqual(canvas.pages("https://canvas.example.edu", "secret", "/api/v1/courses",
                                      {"per_page": 100}, opener), [{"id": 1}, {"id": 2}])
        with self.assertRaises(ValueError):
            canvas.pages("https://canvas.example.edu", "secret", "/api/v1/courses",
                          {}, lambda *args, **kwargs: Response([], '<https://example.net/api/v1/courses>; rel="next"'))

    def test_guided_setup_writes_private_files_without_echoing_token(self):
        new_config = Path(self.temp.name) / "niku" / "canvas.json"
        token = "new-example-token"
        result = canvas.configure({"baseUrl": "canvas.example.edu", "token": token}, new_config)
        self.assertEqual(result, {"ok": True, "baseUrl": "https://canvas.example.edu"})
        self.assertNotIn(token, json.dumps(result))
        self.assertEqual(new_config.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(new_config.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(token, new_config.read_text())
        token_file = new_config.parent / "canvas-token"
        self.assertEqual(token_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(canvas.configured_source(new_config), ("https://canvas.example.edu", token))
        self.assertEqual(canvas.public_settings(new_config), {"baseUrl": "https://canvas.example.edu", "hasToken": True})

    def test_guided_setup_preserves_existing_token_until_replaced(self):
        original = json.loads(self.config.read_text())["tokenFile"]
        result = canvas.configure({"baseUrl": "other.example.edu", "token": ""}, self.config)
        self.assertTrue(result["ok"])
        self.assertEqual(json.loads(self.config.read_text())["tokenFile"], original)
        self.assertEqual(Path(original).read_text(), "example-token")

    def test_guided_setup_rejects_bad_origin_and_missing_token_without_writing(self):
        new_config = Path(self.temp.name) / "niku" / "canvas.json"
        self.assertEqual(canvas.configure({"baseUrl": "https://canvas.example.edu/path", "token": "secret"}, new_config),
                         {"ok": False, "error": "invalid_url"})
        self.assertEqual(canvas.configure({"baseUrl": "canvas.example.edu", "token": ""}, new_config),
                         {"ok": False, "error": "missing_token"})
        self.assertFalse(new_config.exists())

    def test_cli_setup_uses_stdin_and_returns_no_credentials(self):
        config_home = Path(self.temp.name) / "config"
        result = subprocess.run(
            [sys.executable, str(Path(canvas.__file__)), "--configure"],
            input=json.dumps({"baseUrl": "canvas.example.edu", "token": "example-secret"}) + "\n",
            text=True, capture_output=True,
            env={**os.environ, "XDG_CONFIG_HOME": str(config_home)}, check=True,
        )
        self.assertEqual(json.loads(result.stdout), {"ok": True, "baseUrl": "https://canvas.example.edu"})
        self.assertNotIn("example-secret", result.stdout + result.stderr)
        self.assertEqual((config_home / "niku" / "canvas-token").stat().st_mode & 0o777, 0o600)

    def academic(self, section, **kwargs):
        return canvas.academic(section, config_path=self.config,
                               cache_dir=Path(self.temp.name) / "academic", **kwargs)

    def test_academic_cache_is_separate_per_course_and_account(self):
        def opener(request, timeout):
            return Response([{"id": 1, "name": "Work", "submission": {"workflow_state": "submitted"}}])
        first = self.academic("assignments", course="10", now=1000, opener=opener)
        self.assertTrue(first["items"][0]["submitted"])
        cached = self.academic("assignments", course="10", now=1001, cached_only=True)
        self.assertEqual(cached["items"], first["items"])
        self.assertFalse(self.academic("assignments", course="11", cached_only=True)["ok"])
        token = Path(json.loads(self.config.read_text())["tokenFile"])
        token.write_text("another-account-token")
        self.assertFalse(self.academic("assignments", course="10", cached_only=True)["ok"])

    def test_academic_offline_keeps_previous_data(self):
        first = self.academic("courses", now=1000, opener=lambda *a, **kw: Response([{"id": 10, "name": "Math"}]))
        offline = self.academic("courses", now=3000,
                                opener=lambda *a, **kw: (_ for _ in ()).throw(OSError("offline")))
        self.assertTrue(offline["stale"])
        self.assertEqual(first["items"], offline["items"])

    def test_all_assignments_isolates_course_failure_and_keeps_undated(self):
        def opener(request, timeout):
            if "/courses?" in request.full_url:
                return Response([{"id": 10, "name": "Math"}, {"id": 20, "name": "Unavailable"}])
            if "/20/" in request.full_url:
                raise OSError("Forbidden")
            return Response([{"id": 1, "name": "Optional work", "due_at": None,
                              "submission": {"workflow_state": "unsubmitted"}}])
        result = self.academic("assignments", opener=opener)
        self.assertTrue(result["ok"])
        self.assertTrue(result["partial"])
        self.assertIsNone(result["items"][0]["dueAt"])
        self.assertFalse(result["items"][0]["submitted"])

    def test_announcements_strip_markup_and_do_not_load_images(self):
        def opener(request, timeout):
            return Response([{"id": 1, "title": "<img src=x>", "message":
                              '<p>Read &amp; learn</p><img src="https://example.net/tracker"><script>bad()</script>',
                              "html_url": "javascript:alert(1)"}])
        result = self.academic("announcements", course="10", opener=opener)
        self.assertTrue(result["ok"])
        self.assertEqual(result["items"][0]["body"], "Read & learn")
        self.assertEqual(result["items"][0]["url"], "")

    def test_grades_use_published_average_and_keep_zero(self):
        def opener(request, timeout):
            if "/enrollments?" in request.full_url:
                return Response([{"grades": {"current_score": 0, "current_grade": None}}])
            return Response([{"id": 1, "name": "Test", "points_possible": 10,
                              "submission": {"score": 0, "grade": "0", "workflow_state": "graded"}}])
        result = self.academic("grades", course="10", opener=opener)
        self.assertEqual(result["items"][0]["score"], 0)
        self.assertEqual(result["items"][1]["score"], 0)
        self.assertTrue(result["items"][0]["average"])

    def test_materials_fetch_missing_module_items_and_skip_locked_files(self):
        def opener(request, timeout):
            if "/modules?" in request.full_url:
                return Response([{"id": 2, "name": "Week one", "items_count": 1}])
            if "/items?" in request.full_url:
                return Response([{"id": 4, "title": "Page", "type": "Page", "html_url": "/courses/10/pages/intro"}])
            return Response([{"id": 8, "display_name": "Hidden", "locked_for_user": True},
                             {"id": 9, "display_name": "Notes"}])
        result = self.academic("materials", course="10", opener=opener)
        self.assertEqual([i["title"] for i in result["items"]], ["Page", "Notes"])

    def test_planner_completion_is_not_submission(self):
        result = canvas.normalize([], [
            {"plannable_type": "assignment", "plannable_id": 1,
             "plannable": {"due_at": "2026-11-06T12:00:00Z"}, "planner_override": {"marked_complete": True}},
            {"plannable_type": "assignment", "plannable_id": 2,
             "plannable": {"due_at": "2026-11-06T13:00:00Z"}, "submissions": {"submitted": True}}
        ], "https://canvas.example.edu")
        self.assertFalse(result["assignments"][0]["submitted"])
        self.assertTrue(result["assignments"][0]["markedComplete"])
        self.assertTrue(result["assignments"][1]["submitted"])

    def test_missing_or_explicitly_unsubmitted_work_is_not_hidden_by_a_grade(self):
        self.assertFalse(canvas.is_submitted({"missing": True, "workflow_state": "graded", "score": 0}))
        self.assertFalse(canvas.is_submitted({"submitted": False, "graded": True}))
        self.assertTrue(canvas.is_submitted({"submitted": True, "graded": False}))

    def test_invalid_course_never_makes_request(self):
        result = self.academic("grades", course="../users", opener=lambda *a, **kw: self.fail("request"))
        self.assertEqual(result["error"], "invalid_course")

    def test_redirect_cannot_forward_credentials_to_another_origin(self):
        request = canvas.Request("https://canvas.example.edu/api/v1/courses",
                                 headers={"Authorization": "Bearer example-token"})
        handler = canvas.CanvasRedirectHandler()
        for target in ("https://other.example/api/v1/courses", "http://canvas.example.edu/api/v1/courses",
                       "https://canvas.example.edu/login"):
            with self.assertRaises(ValueError):
                handler.redirect_request(request, None, 302, "Found", {}, target)

    def test_changed_account_cannot_reuse_planner_cache(self):
        self.assertTrue(canvas.status(self.config, self.cache, now=1000,
                                      opener=lambda *a, **kw: Response([]))["ok"])
        token = Path(json.loads(self.config.read_text())["tokenFile"])
        token.write_text("different-account")
        result = canvas.status(self.config, self.cache, now=1001,
                               opener=lambda *a, **kw: (_ for _ in ()).throw(OSError("offline")))
        self.assertFalse(result["ok"])

    def test_calendar_keeps_timed_and_all_day_events(self):
        def opener(request, timeout):
            self.assertIn("/calendar_events?", request.full_url)
            self.assertIn("course_10", request.full_url)
            return Response([
                {"id": 1, "title": "Class", "start_at": "2026-11-06T12:00:00Z",
                 "end_at": "2026-11-06T13:00:00Z", "all_day": False},
                {"id": 2, "title": "Holiday", "start_at": "2026-11-07T00:00:00Z",
                 "end_at": "2026-11-08T00:00:00Z", "all_day": True}
            ])
        result = self.academic("calendar", course="10", opener=opener)
        self.assertTrue(result["ok"])
        self.assertEqual([i["allDay"] for i in result["items"]], [False, True])
        self.assertEqual(result["items"][0]["endAt"], "2026-11-06T13:00:00Z")


if __name__ == "__main__":
    unittest.main()
