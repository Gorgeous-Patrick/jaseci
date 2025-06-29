#!/usr/bin/env python3
"""Script to generate a markdown table of top contributors from GitHub."""

import argparse
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple


def get_repo_from_remote() -> Tuple[Optional[str], Optional[str]]:
    """Get repository owner and name from git remote URL."""
    try:
        url = (
            subprocess.check_output(["git", "remote", "get-url", "origin"])
            .decode("utf-8")
            .strip()
        )
        # Match SSH or HTTPS URLs
        match = re.search(r"(?:[:/])([^/]+)/([^/]+?)(?:\.git)?$", url)
        if match:
            return match.group(1), match.group(2)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(
            "Error: Could not determine repository from git remote. Please specify --repo OWNER/NAME."
        )
        return None, None
    return None, None


def fetch_commits(
    owner: str, repo: str, days: int, token: Optional[str] = None
) -> Optional[List[Dict[str, Any]]]:
    """Fetch commit data from GitHub API."""
    since_date = (datetime.now(timezone.utc) - timedelta(days=days)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )

    all_commits = []
    params = {"since": since_date, "per_page": 100}
    url: str | None = (
        f"https://api.github.com/repos/{owner}/{repo}/commits?{urllib.parse.urlencode(params)}"
    )

    headers = {
        "Accept": "application/vnd.github.v3+json",
    }
    if token:
        headers["Authorization"] = f"token {token}"

    while url:
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req) as response:
                commits = json.loads(response.read().decode("utf-8"))

                if not commits:
                    break

                all_commits.extend(commits)

                link_header = response.getheader("Link")
                url = None
                if link_header:
                    links = link_header.split(", ")
                    for link in links:
                        parts = link.split("; ")
                        if 'rel="next"' in parts[1]:
                            url = parts[0].strip("<>")
                            break

        except urllib.error.HTTPError as e:
            print(f"Error fetching commits: {e}")
            if e.code == 401:
                print(
                    "Error: Invalid GitHub token. Please check your GITHUB_TOKEN environment variable."
                )
            elif e.code == 404:
                print(
                    f"Error: Repository '{owner}/{repo}' not found. Please check the repository details."
                )
            return None
        except json.JSONDecodeError as e:
            print(f"Error decoding JSON response: {e}")
            return None

    return all_commits


def process_contributors(
    commits: List[Dict[str, Any]], days: int
) -> List[Dict[str, Any]]:
    """Process commits to get contributor stats for a specific period."""
    since_date = (datetime.now(timezone.utc) - timedelta(days=days)).date()
    contributors: Dict[str, Dict[str, Any]] = defaultdict(
        lambda: {"commits": 0, "active_days": set()}
    )

    for commit in commits:
        commit_date: date = datetime.strptime(
            commit["commit"]["author"]["date"], "%Y-%m-%dT%H:%M:%SZ"
        ).date()
        if commit_date >= since_date and commit["author"]:
            author_login = commit["author"]["login"]
            contributors[author_login]["commits"] += 1
            contributors[author_login]["active_days"].add(commit_date)

    return sorted(
        [
            {
                "login": login,
                "commits": data["commits"],
                "active_days": len(data["active_days"]),
            }
            for login, data in contributors.items()
        ],
        key=lambda x: x["commits"],
        reverse=True,
    )


def generate_markdown_table(contributors: List[Dict[str, Any]], days: int, repo: str) -> str:
    """Generate a markdown table from contributor data and return as string."""
    if not contributors:
        return f"No contributions found in the last {days} days for {repo}.\n"

    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=days)

    lines = []
    lines.append(
        f"### Top contributors in the last {days} days "
        f"({start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')})\n"
    )
    lines.append("| Contributor | Commits | Active Days |")
    lines.append("|---|---|---|")
    for contributor in contributors:
        login = contributor["login"]
        commits = contributor["commits"]
        active_days = contributor["active_days"]
        lines.append(f"| [@{login}](https://github.com/{login}) | {commits} | {active_days} |")
    lines.append("\n")
    return "\n".join(lines)

def get_tabs_css() -> str:
    """Return CSS for the tab and table design (dark tab bar, clear selection, aligned tabs, responsive)."""
    return """
<style>
#tabs {
    display: flex;
    justify-content: space-between;
    padding: 0;
    margin: 0 0 1em 0;
    border-bottom: 2px solid #222;
    background: #23272e;
    list-style: none;
    width: 100%;
}
#tabs li {
    flex: 1 1 0;
    text-align: center;
    padding: 0.7em 1.5em;
    margin: 0;
    cursor: pointer;
    border: 1px solid #222;
    border-bottom: none;
    background: #23272e;
    color: #bfc7d5;
    border-radius: 8px 8px 0 0;
    transition: background 0.2s, color 0.2s;
    font-weight: 500;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
#tabs li.active, #tabs li:hover {
    background: #181b20;
    color: #fff;
    font-weight: bold;
    border-bottom: 2px solid #181b20;
    box-shadow: 0 -2px 8px #181b20;
    z-index: 2;
}
#tabs li:first-child {
    text-align: left;
    justify-content: flex-start;
}
#tabs li:nth-child(2) {
    text-align: center;
    justify-content: center;
}
#tabs li:last-child {
    text-align: right;
    justify-content: flex-end;
}
@media (max-width: 700px) {
    #tabs {
        flex-direction: column;
        border-bottom: none;
    }
    #tabs li {
        border-radius: 8px 8px 0 0;
        border-bottom: 1px solid #222;
        border-right: none;
        text-align: left;
    }
    #tabs li.active, #tabs li:hover {
        border-bottom: 2px solid #181b20;
    }
}
.tabcontent {
    background: #181b20;
    border: 1px solid #222;
    border-radius: 0 0 8px 8px;
    padding: 1.5em;
    margin-bottom: 2em;
    box-shadow: 0 2px 8px rgba(0,0,0,0.12);
    color: #e0e6ed;
}
.tabcontent table {
    width: 100%;
    border-collapse: collapse;
    margin: 1em 0;
    font-size: 1em;
    background: #23272e;
    color: #e0e6ed;
}
.tabcontent th, .tabcontent td {
    border: 1px solid #222;
    padding: 0.7em 1em;
    text-align: left;
}
.tabcontent th {
    background: #181b20;
    color: #7ecfff;
    font-weight: 600;
}
.tabcontent tr:nth-child(even) {
    background: #23272e;
}
.tabcontent tr:hover {
    background: #2a313a;
}
</style>
"""

def get_tabs_js(num_tabs: int) -> str:
    """Return JS for tab switching."""
    return f"""
<script>
function showTab(idx) {{
    var n = {num_tabs};
    for (var i = 0; i < n; i++) {{
        document.getElementById('tabcontent'+i).style.display = (i === idx) ? 'block' : 'none';
        var tab = document.getElementById('tab'+i);
        if (i === idx) {{
            tab.classList.add('active');
        }} else {{
            tab.classList.remove('active');
        }}
    }}
}}
</script>
"""

def get_tabs_html(repo_tables: list) -> str:
    """Return HTML for the tab headers, aligned across the page."""
    tabs = []
    for idx, (repo, _) in enumerate(repo_tables):
        active = "active" if idx == 0 else ""
        tabs.append(f'<li class="{active}" onclick="showTab({idx})" id="tab{idx}">{repo}</li>')
    return '<ul id="tabs">\n' + "\n".join(tabs) + '\n</ul>'

def get_tab_contents_html(repo_tables: List[Tuple[str, str]]) -> str:
    """Return HTML for the tab contents."""
    contents = []
    for idx, (repo, table) in enumerate(repo_tables):
        display = "block" if idx == 0 else "none"
        contents.append(
            f'<div id="tabcontent{idx}" class="tabcontent" style="display:{display};">\n{table}\n</div>'
        )
    return "\n".join(contents)

def print_tabbed_tables(repo_tables: List[Tuple[str, str]]) -> None:
    """Prints HTML tabbed view for multiple repo tables with separated HTML/CSS/JS."""
    html = []
    html.append(get_tabs_css())
    html.append('<div style="margin-bottom: 1em;">')
    html.append(get_tabs_html(repo_tables))
    html.append('</div>')
    html.append(get_tab_contents_html(repo_tables))
    html.append(get_tabs_js(len(repo_tables)))
    print("\n".join(html))

# You can define your default repos here if you want to hardcode them
DEFAULT_MAIN_REPO = "jaclang/jaclang"
DEFAULT_EXTRA_REPOS = [
    "jaclang/pyjac",
    "jaclang/jaseci"
]

def main() -> None:
    """Run the script."""
    owner, repo = get_repo_from_remote()

    parser = argparse.ArgumentParser(
        description="Generate a markdown table of top contributors from GitHub."
    )
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="Generate an additional table for a specific number of days.",
    )
    parser.add_argument(
        "--repo",
        type=str,
        default=f"{owner}/{repo}" if owner and repo else DEFAULT_MAIN_REPO,
        help="GitHub repository in 'owner/repo' format.",
    )
    parser.add_argument(
        "--extra-repos",
        type=str,
        nargs="*",
        default=DEFAULT_EXTRA_REPOS,
        help="Additional public repos in 'owner/repo' format (space separated).",
    )

    args = parser.parse_args()

    if not args.repo:
        parser.print_help()
        return

    repos = [args.repo] + args.extra_repos

    periods = []
    if args.days is not None:
        periods.append(args.days)
    for p in [7, 30, 180, 365]:
        if p not in periods:
            periods.append(p)
    if not periods:
        return

    token = os.getenv("GITHUB_TOKEN")

    repo_tables = []
    for repo_full in repos:
        owner, repo = repo_full.split("/")
        max_days = max(periods)
        all_commits = fetch_commits(owner or "", repo or "", max_days, token)
        if all_commits is None:
            table = f"Could not fetch data for {repo_full}."
            repo_tables.append((repo_full, table))
            continue
        table = ""
        for days in periods:
            contributors = process_contributors(all_commits, days)
            if contributors:
                table += generate_markdown_table(contributors, days, repo_full)
        repo_tables.append((repo_full, table if table else f"No contributions found for {repo_full}."))

    print_tabbed_tables(repo_tables)

if __name__ == "__main__":
    main()
