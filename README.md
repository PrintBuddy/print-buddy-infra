# print-buddy-infra

Deployment configuration for [print-buddy](https://github.com/rbenatuilv/print-buddy): `docker-compose.yml` and `deploy.sh`, previously untracked files sitting directly on the deploy host. Moved here so deploy changes are versioned and reviewable like everything else.

## Layout

This repo is expected to sit alongside the three app repos:

```
some-parent-dir/
├── backend/
├── bot/
├── frontend/
└── print-buddy-infra/   <- this repo
```

`docker-compose.yml`'s build contexts (`../backend`, `../bot`, `../frontend/app`) and `deploy.sh` both assume this sibling layout.

## Setup

```bash
cp .env.example .env
# fill in BACKEND_PORT, CUPS_HOST, VITE_*, POSTGRES_*
./deploy.sh
```

`deploy.sh` pulls the latest `main` for each of the three app repos (`git fetch && git reset --hard origin/main && git clean -fd`), then builds and starts everything via `docker compose`.

```
Usage: ./deploy.sh [OPTIONS]

  -s, --service [name]    Service to deploy (frontend, backend, bot, all). Default: all
  -b, --bump [type]       Version bump type (major, minor, fix).
  -c, --clean             Perform a clean build using --no-cache.
  -h, --help              Show this help message.
```

Since `deploy.sh` always deploys whatever is on each repo's `main`, work on a feature branch in any of the three app repos never goes live until it's merged and pushed to `main` — the next `./deploy.sh` run picks it up automatically.

## Fixed from the original untracked version

- Postgres credentials were hardcoded in `docker-compose.yml` (`printowner`/a plaintext password) instead of pulled from `.env` like everything else in the file.
- The Postgres healthcheck had a typo (`-d {POSTGRES_DB}` — missing `$`) that meant it wasn't actually checking readiness against the real database name.
- `frontend`/`bot` only waited for `backend`'s container to *start* (plain `depends_on`), not for its healthcheck to pass — both now use `condition: service_healthy`, matching how `postgres`'s dependency was already done correctly.
- Postgres's port was exposed on all interfaces (`5432:5432`); now bound to loopback only (`127.0.0.1:5432:5432`) unless something outside the compose network genuinely needs direct access.
- No `.env.example` existed at all.

## Planned follow-up: faster deploys

The current model rebuilds every service from source on the deploy host on every run (`git reset --hard` + `docker compose build`) — slow, and it means the host needs git credentials/source checkouts for all three repos just to build images. The plan is:

1. Each app repo's CI builds and pushes an image to GHCR on merge to `main`, tagged with the commit SHA.
2. This repo's `docker-compose.yml` switches from `build: ../backend` (etc.) to `image: ghcr.io/rbenatuilv/print-buddy-backend:${TAG:-latest}` per service.
3. `deploy.sh` collapses to `docker compose pull && docker compose up -d` — no source checkout, no rebuild.
4. Rollback becomes: set `TAG` to a previous SHA and re-run `docker compose up -d`.

Not done yet — worth doing once the app-repo fixes this was written alongside have been merged and deployed at least once via the current flow, so the deploy mechanism and the app aren't both changing at the same time.
