#!/usr/bin/env python3
"""
Bootstraps the ephemeral E2E stack: waits for the backend to be healthy,
registers the two fixed test users, elevates one to admin, and waits for
the CUPS sidecar's virtual "PDF" printer to be auto-discovered by the
backend's printer_updater scheduler job.

Uses only the standard library (no pip installs needed in CI) plus
`docker compose exec` (already available on the runner) for the one
direct-DB write that has no corresponding API (there's no
create-admin-user endpoint — see the E2E plan's notes).

These usernames/passwords are also hardcoded in the Playwright specs
(tests/*.spec.ts) — keep both in sync if you change them here.
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000/api"
COMPOSE_FILE = "docker-compose.e2e.yml"

USERS = [
    {"username": "e2e_user", "name": "E2E", "surname": "User", "pwd": "E2ePassword123!"},
    {"username": "e2e_admin", "name": "E2E", "surname": "Admin", "pwd": "E2ePassword123!"},
]


def http_json(method, path, body=None, token=None):
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status, json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def wait_for_health(timeout=90):
    print("Waiting for backend health...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            status, body = http_json("GET", "/health")
            if status == 200 and body.get("status") == "ok":
                print("Backend is healthy.")
                return
        except Exception:
            pass
        time.sleep(2)
    print("Backend never became healthy.", file=sys.stderr)
    sys.exit(1)


def register_users():
    for user in USERS:
        status, body = http_json("POST", "/auth/register", {
            "username": user["username"],
            "name": user["name"],
            "surname": user["surname"],
            "pwd": user["pwd"],
        })
        if status not in (200, 201, 409):
            print(f"Failed to register {user['username']}: {status} {body}", file=sys.stderr)
            sys.exit(1)
        print(f"Registered {user['username']} (status {status}).")


def elevate_and_fund_users():
    sql = (
        "UPDATE \"user\" SET is_admin = true, balance = 100, credit_limit = 0 "
        "WHERE username = 'e2e_admin'; "
        "UPDATE \"user\" SET balance = 100, credit_limit = 0 "
        "WHERE username = 'e2e_user';"
    )
    result = subprocess.run(
        ["docker", "compose", "-f", COMPOSE_FILE, "exec", "-T", "postgres",
         "psql", "-U", "e2e", "-d", "printbuddy-e2e-dev", "-c", sql],
        capture_output=True, text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)


def login(username, pwd):
    status, body = http_json("POST", "/auth/login", {"username": username, "pwd": pwd})
    if status != 200:
        print(f"Login failed for {username}: {status} {body}", file=sys.stderr)
        sys.exit(1)
    return body["token"]


def wait_for_pdf_printer(token, timeout=120):
    print("Waiting for the PDF printer to be auto-discovered...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        status, body = http_json("GET", "/printers", token=token)
        if status == 200 and any(p.get("name") == "PDF" for p in body):
            print("PDF printer is registered.")
            return
        time.sleep(3)
    print("PDF printer never appeared — printer_updater may not have ticked yet, "
          "or the CUPS sidecar failed to register its queue.", file=sys.stderr)
    sys.exit(1)


def price_the_pdf_printer():
    # The printer row is auto-created from CUPS discovery data alone (name/
    # location/status), which carries no pricing — it lands with the
    # PrinterCreate schema's default price_per_page_bw=0.0. A free print job
    # wouldn't meaningfully exercise the balance-debit path the E2E print
    # flow test is meant to lock in, so give it a real, non-zero price.
    sql = "UPDATE printer SET price_per_page_bw = 0.10, admits_color = false WHERE name = 'PDF';"
    result = subprocess.run(
        ["docker", "compose", "-f", COMPOSE_FILE, "exec", "-T", "postgres",
         "psql", "-U", "e2e", "-d", "printbuddy-e2e-dev", "-c", sql],
        capture_output=True, text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    wait_for_health()
    register_users()
    elevate_and_fund_users()
    user_token = login("e2e_user", "E2ePassword123!")
    wait_for_pdf_printer(user_token)
    price_the_pdf_printer()
    print("Seeding complete.")
