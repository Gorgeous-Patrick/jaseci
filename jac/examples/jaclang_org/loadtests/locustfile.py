"""Authenticated JacYac browsing, with an optional social write workload."""

import logging
import random
import time
from collections import deque
from uuid import uuid4

import gevent
from locust import HttpUser, events, task
from locust.exception import StopUser
from locust.runners import MasterRunner, WorkerRunner

from protocol import ContractError, load_accounts, node_id, report

logger = logging.getLogger(__name__)


@events.init_command_line_parser.add_listener
def arguments(parser):
    parser.add_argument("--accounts", default="local.accounts.json", env_var="JACYAC_ACCOUNTS")
    parser.add_argument("--walker-prefix", default="/api/social_graph/walker")
    parser.add_argument(
        "--write-workload", action="store_true", help="enable post/like/comment/delete tasks"
    )
    parser.add_argument("--think-min", type=float, default=1.0)
    parser.add_argument("--think-max", type=float, default=3.0)
    parser.add_argument(
        "--post-interval", type=float, default=10.1,
        help="minimum seconds between post/comment attempts per user",
    )
    parser.add_argument("--max-failure-ratio", type=float, default=0.01)
    parser.add_argument("--max-p95-ms", type=float, default=1000.0)
    parser.add_argument("--min-requests", type=int, default=100)


@events.test_start.add_listener
def prepare(environment, **kwargs):
    options = environment.parsed_options
    environment.jacyac_setup_failed = False
    try:
        if not 0 <= options.think_min <= options.think_max:
            raise ValueError("Require 0 <= --think-min <= --think-max")
        if options.post_interval < 0 or not 0 <= options.max_failure_ratio <= 1:
            raise ValueError("Invalid interval or failure ratio")
        if options.min_requests < 1 or options.max_p95_ms <= 0:
            raise ValueError("Request count and p95 limit must be positive")
        if isinstance(environment.runner, (MasterRunner, WorkerRunner)):
            raise ValueError(
                "This scenario requires a single Locust process and a unique account per user"
            )
        accounts = load_accounts(
            options.accounts, environment.host or JacYacUser.host, options.walker_prefix
        )
        environment.jacyac_accounts = deque(accounts)
        logger.info("Loaded %d distinct JacYac accounts", len(accounts))
    except (OSError, ValueError, TypeError) as exc:
        abort(environment, str(exc))


def abort(environment, reason):
    logger.error("JacYac setup failed: %s", reason)
    environment.jacyac_setup_failed = True
    environment.process_exit_code = 2
    gevent.spawn(environment.runner.quit)


@events.quitting.add_listener
def check_result(environment, **kwargs):
    if getattr(environment, "jacyac_setup_failed", False):
        environment.process_exit_code = 2
        return
    options = environment.parsed_options
    total = environment.stats.total
    if environment.runner.exceptions:
        logger.error("Locust user code raised an exception")
        environment.process_exit_code = 1
    elif total.num_requests < options.min_requests:
        logger.error("Too few samples: %d < %d", total.num_requests, options.min_requests)
        environment.process_exit_code = 1
    elif total.fail_ratio > options.max_failure_ratio:
        logger.error("Failure ratio %.3f exceeds %.3f", total.fail_ratio, options.max_failure_ratio)
        environment.process_exit_code = 1
    elif total.get_response_time_percentile(0.95) > options.max_p95_ms:
        logger.error("p95 exceeds %.0f ms", options.max_p95_ms)
        environment.process_exit_code = 1
    else:
        environment.process_exit_code = 0


class JacYacUser(HttpUser):
    host = "http://127.0.0.1:8000"

    def wait_time(self):
        return random.uniform(self.options.think_min, self.options.think_max)

    def on_start(self):
        self.options = self.environment.parsed_options
        self.account = None
        pool = getattr(self.environment, "jacyac_accounts", deque())
        if not pool:
            abort(
                self.environment, "Not enough accounts: provision at least one per concurrent user"
            )
            raise StopUser()
        self.account = pool.popleft()
        self.client.trust_env = False
        self.client.headers["Authorization"] = f"Bearer {self.account['token']}"
        self.next_post_at = time.monotonic() + self.options.post_interval
        self.pending_tweets = set()
        profile = self.walk("get_profile", {}, "profile")
        if profile is None or profile["profile"].get("username") != self.account["username"]:
            abort(self.environment, "Token/profile mismatch; recreate the account fixture")
            raise StopUser()
        feed = self.walk("load_feed", {}, "list")
        if not feed:
            abort(self.environment, "Fixture has no feed; run seed.py before measuring")
            raise StopUser()

    def on_stop(self):
        if self.account is not None:
            for tweet_id in list(getattr(self, "pending_tweets", ())):
                if self.walk("delete_tweet", {"tweet_id": tweet_id}, "success") is None:
                    logger.warning("Could not remove this run's post %s", tweet_id)
            self.environment.jacyac_accounts.append(self.account)

    def walk(self, name, payload, kind):
        path = f"{self.options.walker_prefix.rstrip('/')}/{name}"
        with self.client.post(
            path, json=payload, name=name, timeout=(5, 30),
            allow_redirects=False, catch_response=True,
        ) as response:
            if not 200 <= response.status_code < 300:
                response.failure(f"HTTP {response.status_code}")
                return None
            try:
                result = report(response.json(), kind)
            except (ValueError, TypeError, KeyError) as exc:
                response.failure(
                    str(exc) if isinstance(exc, ContractError) else "Invalid JSON response"
                )
                return None
            response.success()
            return result

    def read_feed(self):
        self.walk("load_feed", {"search_query": ""}, "list")

    def social_write(self):
        # Delete only posts made by this virtual user in this run. Retain the
        # fixture posts so later read-only runs exercise the same graph.
        if self.pending_tweets:
            tweet_id = next(iter(self.pending_tweets))
            if self.walk("delete_tweet", {"tweet_id": tweet_id}, "success") is not None:
                self.pending_tweets.remove(tweet_id)
                self.read_feed()
            return
        if time.monotonic() < self.next_post_at:
            self.read_feed()
            return
        self.next_post_at = time.monotonic() + self.options.post_interval
        tweet = self.walk("create_tweet", {
            "content": f"Locust {uuid4().hex} #loadtest",
        }, "tweet")
        if tweet is None:
            return
        tweet_id = node_id(tweet)
        self.pending_tweets.add(tweet_id)
        self.read_feed()
        if self.walk("like_tweet", {"tweet_id": tweet_id}, "like") is not None:
            self.read_feed()
        # Comments share the posting quota, so spread the two writes apart.
        self.wait_for_post_slot()
        comment = self.walk(
            "add_comment", {"tweet_id": tweet_id, "content": "Locust comment"}, "success"
        )
        if comment is not None:
            self.read_feed()
        if self.walk("delete_tweet", {"tweet_id": tweet_id}, "success") is not None:
            self.pending_tweets.remove(tweet_id)
            self.read_feed()

    def wait_for_post_slot(self):
        gevent.sleep(max(0, self.next_post_at - time.monotonic()))
        self.next_post_at = time.monotonic() + self.options.post_interval

    @task
    def browse(self):
        choice = random.randrange(100)
        if choice < 10 and self.options.write_workload:
            self.social_write()
        elif choice < 50:
            self.read_feed()
        elif choice < 65:
            self.walk("get_all_profiles", {}, "list")
        elif choice < 75:
            self.walk("get_profile", {}, "profile")
        elif choice < 85:
            self.walk("get_channels", {}, "list")
        elif choice < 95:
            self.walk("get_trending", {}, "list")
        else:
            self.walk("load_feed", {"search_query": "jac"}, "list")
