"""Exercise Locust's statistics and failure gates without an external service."""

from locust.env import Environment
from locust.event import Events

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from requests import Response
from requests.adapters import BaseAdapter

from locustfile import JacYacUser, check_result, prepare


class ResponseAdapter(BaseAdapter):
    def __init__(self, status, body):
        self.status, self.body = status, body

    def send(self, request, **kwargs):
        response = Response()
        response.status_code = self.status
        response._content = json.dumps(self.body).encode()
        response.url = request.url
        response.request = request
        return response

    def close(self):
        pass


class LocustTests(unittest.TestCase):
    def setUp(self):
        self.options = SimpleNamespace(
            think_min=1, think_max=3, post_interval=10.1, max_failure_ratio=0.01,
            max_p95_ms=1000, min_requests=1, headless=True, walker_prefix="/walker",
        )
        self.environment = Environment(
            user_classes=[JacYacUser], events=Events(),
            host="http://localhost:8000", parsed_options=self.options,
        )
        self.runner = self.environment.create_local_runner()
        self.user = JacYacUser(self.environment)
        self.user.options = self.options
        self.addCleanup(self.runner.quit)

    def respond(self, status, body):
        self.user.client.mount("http://", ResponseAdapter(status, body))
        return self.user.walk("load_feed", {}, "list")

    def test_http_200_posting_denial_is_a_locust_failure(self):
        result = self.respond(200, {"ok": True, "data": {"reports": [{
            "message": "Posting limit reached", "retry_after_seconds": 10,
        }]}})
        self.assertIsNone(result)
        self.assertEqual(self.environment.stats.total.num_requests, 1)
        self.assertEqual(self.environment.stats.total.num_failures, 1)
        check_result(self.environment)
        self.assertEqual(self.environment.process_exit_code, 1)

    def test_http_error_cannot_be_overridden_by_success_envelope(self):
        self.assertIsNone(self.respond(503, {"ok": True, "data": {"reports": [[]]}}))
        self.assertEqual(self.environment.stats.total.num_failures, 1)

    def test_valid_response_reaches_stats_and_gate(self):
        self.assertEqual(self.respond(200, {"ok": True, "data": {"reports": [[]]}}), [])
        self.assertEqual(self.environment.stats.total.num_failures, 0)
        check_result(self.environment)
        self.assertEqual(self.environment.process_exit_code, 0)

    def test_zero_traffic_cannot_pass(self):
        check_result(self.environment)
        self.assertEqual(self.environment.process_exit_code, 1)

    def test_missing_fixture_fails_setup_and_stops_runner(self):
        with tempfile.TemporaryDirectory() as directory:
            self.options.accounts = str(Path(directory) / "missing.accounts.json")
            with patch("locustfile.gevent.spawn") as spawn:
                prepare(self.environment)
                spawn.assert_called_once_with(self.runner.quit)
            check_result(self.environment)
            self.assertEqual(self.environment.process_exit_code, 2)


if __name__ == "__main__":
    unittest.main()
