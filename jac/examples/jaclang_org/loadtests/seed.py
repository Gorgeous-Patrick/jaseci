"""Provision dedicated users and a nonempty social graph before measuring load."""

import argparse
import json
import os
import secrets
import time
from pathlib import Path

import requests

from protocol import load_accounts, node_id, report, solve_challenge, unwrap


def positive(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="http://127.0.0.1:8000")
    parser.add_argument("--walker-prefix", default="/api/social_graph/walker")
    parser.add_argument("--accounts", type=Path, default=Path("local.accounts.json"))
    parser.add_argument("--users", type=positive, default=5)
    parser.add_argument("--posts-per-user", type=positive, default=1)
    parser.add_argument("--post-interval", type=float, default=10.1)
    parser.add_argument("--follows-per-user", type=int, default=3)
    parser.add_argument("--resume", action="store_true", help="reuse a partial or existing seed")
    args = parser.parse_args()
    args.host = args.host.rstrip("/")
    args.walker_prefix = args.walker_prefix.rstrip("/")
    if args.post_interval < 0 or args.follows_per_user < 0:
        parser.error("interval and follow count must be nonnegative")
    if args.accounts.exists() and not args.resume:
        parser.error("account file already exists; use --resume or a new filename")
    accounts = load_accounts(args.accounts, args.host, args.walker_prefix) if args.resume else []
    if len(accounts) > args.users:
        parser.error("--users cannot be smaller than the existing account count")
    session = requests.Session()
    session.trust_env = False

    def post(path, payload):
        response = session.post(
            args.host + path, json=payload, timeout=(5, 30), allow_redirects=False
        )
        if not 200 <= response.status_code < 300:
            raise RuntimeError(
                f"{path}: HTTP {response.status_code}. For 429, check registration/posting "
                "limits on the test server; progress is saved for --resume."
            )
        return response.json()

    def walk(name, payload, kind):
        return report(post(f"{args.walker_prefix}/{name}", payload), kind)

    def save():
        args.accounts.parent.mkdir(parents=True, exist_ok=True)
        document = {"host": args.host, "walker_prefix": args.walker_prefix, "accounts": accounts}
        fd = os.open(args.accounts, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(document, stream, indent=2)
            stream.write("\n")

    prefix = "locust_" + secrets.token_hex(4)
    for index in range(len(accounts), args.users):
        session.headers.pop("Authorization", None)
        challenge = solve_challenge(unwrap(post("/user/register/challenge", {})))
        username = f"{prefix}_{index:05d}"
        data = unwrap(post("/user/register", {
            "identities": [{"type": "username", "value": username}],
            "credential": {"type": "password", "password": secrets.token_urlsafe(24)},
            "challenge": challenge,
        }))
        if not isinstance(data.get("token"), str) or not data["token"]:
            raise RuntimeError("Registration returned no token")
        accounts.append({"username": username, "token": data["token"]})
        save()
        print(f"Registered {len(accounts)}/{args.users}", flush=True)

    for account in accounts:
        session.headers["Authorization"] = f"Bearer {account['token']}"
        bundle = walk("setup_profile", {
            "username": account["username"], "bio": "Dedicated Locust test account",
        }, "profile")
        account["profile_id"] = node_id(bundle["profile"])
        tweets = bundle.get("tweets", [])
        for index in range(len(tweets), args.posts_per_user):
            if index > 0:
                time.sleep(args.post_interval)
            tweet = walk("create_tweet", {
                "content": f"Locust fixture {index} by {account['username']} #jac #loadtest",
            }, "tweet")
            tweets.append(tweet)
        account["tweet_id"] = node_id(tweets[0])
        save()

    for index, account in enumerate(accounts):
        session.headers["Authorization"] = f"Bearer {account['token']}"
        bundle = walk("get_profile", {}, "profile")
        followed = {node_id(p) for p in bundle.get("following", [])}
        for offset in range(1, min(args.follows_per_user, len(accounts) - 1) + 1):
            target = accounts[(index + offset) % len(accounts)]["profile_id"]
            if target not in followed:
                walk("follow_user", {"target_id": target}, "success")
        if not walk("load_feed", {}, "list"):
            raise RuntimeError("Seeded user's feed is empty")

    session.headers["Authorization"] = f"Bearer {accounts[0]['token']}"
    if not accounts[0].get("channel_id"):
        channel = walk("create_channel", {
            "name": "Locust " + accounts[0]["username"],
            "description": "Dedicated load-test channel",
        }, "channel")
        accounts[0]["channel_id"] = node_id(channel["channel"])
        save()
    session.close()
    print(f"Ready: {len(accounts)} accounts saved to {args.accounts} (contains session tokens).")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, requests.RequestException) as exc:
        raise SystemExit(str(exc)) from None
