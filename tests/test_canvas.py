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


if __name__ == "__main__":
    unittest.main()
