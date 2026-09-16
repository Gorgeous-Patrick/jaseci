"""Failure cases that would otherwise make a load test report false success."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from protocol import ContractError, load_accounts, report, solve_challenge


def envelope(value):
    return {"ok": True, "data": {"reports": [value]}}


class ProtocolTests(unittest.TestCase):
    def test_http_success_can_contain_application_failure(self):
        bodies = [
            {"ok": False, "error": {"code": "EXECUTION_ERROR"}},
            envelope({"ok": False, "error": "No such user"}),
            envelope({"message": "Posting limit reached", "retry_after_seconds": 10}),
            envelope({"message": "Posting is unavailable", "retry_after_seconds": 0}),
            {"ok": True, "data": {"reports": []}},
            {"ok": True, "data": {"reports": [[], []]}},
            {"ok": True, "data": {}},
            {"ok": True, "data": None},
            "<html>login</html>",
        ]
        for body in bodies:
            with self.subTest(body=body), self.assertRaises(ContractError):
                report(body, "tweet")

    def test_node_id_required_for_write_followups(self):
        for tweet in ({"id": "wrong-contract", "content": "hi"}, {"_jac_id": ""}):
            with self.subTest(tweet=tweet), self.assertRaises(ContractError):
                report(envelope(tweet), "tweet")
        tweet = {"_jac_id": "abc123", "content": "hi", "author_username": "alice"}
        self.assertEqual(report(envelope(tweet), "tweet"), tweet)

    def test_unlike_and_empty_lists_are_valid(self):
        self.assertEqual(report(envelope([]), "list"), [])
        self.assertEqual(report(envelope({"liked": False}), "like"), {"liked": False})
        with self.assertRaises(ContractError):
            report(envelope({"success": False}), "success")

    def test_challenge_includes_maximum_and_zero(self):
        for number in (0, 7):
            data = {"required": True, "challenge": {
                "salt": "fixture:", "max_number": number,
                "target": hashlib.sha256(f"fixture:{number}".encode()).hexdigest(),
                "token": "challenge-token",
            }}
            self.assertEqual(solve_challenge(data), {"token": "challenge-token", "number": number})
        self.assertIsNone(solve_challenge({"required": False}))
        with self.assertRaises(ContractError):
            solve_challenge({"required": True, "challenge": {"max_number": 100_001}})

    def test_accounts_cannot_cross_hosts_or_reuse_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.accounts.json"
            document = {"host": "http://localhost:8000", "walker_prefix": "/walker",
                        "accounts": [{"username": "alice", "token": "token-a"}]}
            path.write_text(json.dumps(document))
            self.assertEqual(len(load_accounts(path, document["host"], "/walker")), 1)
            with self.assertRaisesRegex(ValueError, "host"):
                load_accounts(path, "https://example.invalid", "/walker")
            with self.assertRaisesRegex(ValueError, "prefix"):
                load_accounts(path, document["host"], "/api/social_graph/walker")
            for duplicate in ({"username": "bob", "token": "token-a"},
                              {"username": "alice", "token": "token-b"}):
                document["accounts"] = [{"username": "alice", "token": "token-a"}, duplicate]
                path.write_text(json.dumps(document))
                with self.assertRaisesRegex(ValueError, "Duplicate"):
                    load_accounts(path, document["host"], "/walker")


if __name__ == "__main__":
    unittest.main()
