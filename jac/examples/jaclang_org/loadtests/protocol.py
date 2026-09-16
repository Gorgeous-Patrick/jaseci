"""JacYac's HTTP contract, shared by provisioning and Locust."""

import hashlib
import json
from pathlib import Path


class ContractError(ValueError):
    """A response did not represent a successful application operation."""


def unwrap(body):
    if not isinstance(body, dict) or body.get("ok") is not True:
        error = body.get("error") if isinstance(body, dict) else None
        code = error.get("code", "unknown") if isinstance(error, dict) else "unknown"
        raise ContractError(f"API error: {code}")
    if not isinstance(body.get("data"), dict):
        raise ContractError("Missing data object")
    return body["data"]


def node_id(node):
    value = node.get("_jac_id") if isinstance(node, dict) else None
    if not isinstance(value, str) or not value:
        raise ContractError("Missing node _jac_id")
    return value


def report(body, kind):
    reports = unwrap(body).get("reports")
    if not isinstance(reports, list) or len(reports) != 1:
        raise ContractError("Expected exactly one walker report")
    value = reports[0]
    if isinstance(value, dict):
        if "retry_after_seconds" in value:
            raise ContractError("PostingDenied")
        if value.get("ok") is False or value.get("error"):
            raise ContractError("Walker business error")
    if kind == "list":
        valid = isinstance(value, list)
    elif kind == "profile":
        valid = isinstance(value, dict) and isinstance(value.get("profile"), dict)
        if valid:
            node_id(value["profile"])
    elif kind == "tweet":
        node_id(value)
        valid = isinstance(value.get("content"), str) and bool(value.get("author_username"))
    elif kind == "like":
        valid = isinstance(value, dict) and isinstance(value.get("liked"), bool)
    elif kind == "success":
        valid = isinstance(value, dict) and value.get("success") is True
    elif kind == "channel":
        valid = isinstance(value, dict) and isinstance(value.get("channel"), dict)
        if valid:
            node_id(value["channel"])
    else:
        raise ValueError(f"Unknown report kind: {kind}")
    if not valid:
        raise ContractError(f"Invalid {kind} report")
    return value


def solve_challenge(data):
    if data.get("required") is False:
        return None
    challenge = data.get("challenge", {})
    maximum = challenge.get("max_number")
    if not isinstance(maximum, int) or not 0 <= maximum <= 100_000:
        raise ContractError("Invalid registration challenge")
    for number in range(maximum + 1):
        digest = hashlib.sha256(f"{challenge['salt']}{number}".encode()).hexdigest()
        if digest == challenge["target"]:
            return {"token": challenge["token"], "number": number}
    raise ContractError("Registration challenge has no solution")


def load_accounts(path, host, walker_prefix):
    document = json.loads(Path(path).read_text())
    if document.get("host", "").rstrip("/") != host.rstrip("/"):
        raise ValueError("Account file belongs to a different --host")
    if document.get("walker_prefix") != walker_prefix.rstrip("/"):
        raise ValueError("Account file belongs to a different --walker-prefix")
    accounts = document.get("accounts")
    if not isinstance(accounts, list) or not accounts:
        raise ValueError("Account file contains no accounts; run seed.py first")
    for account in accounts:
        if not isinstance(account, dict) or not all(
            isinstance(account.get(key), str) and account[key]
            for key in ("username", "token")
        ):
            raise ValueError("Every account needs a username and token")
    for key in ("username", "token"):
        if len({a[key] for a in accounts}) != len(accounts):
            raise ValueError(f"Duplicate {key} in account file")
    return accounts
