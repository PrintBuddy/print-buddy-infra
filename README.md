# print-buddy-infra

Deployment configuration for the three Print Buddy app repos — [print-buddy](https://github.com/printbuddy/print-buddy) (backend), [print-bot](https://github.com/printbuddy/print-bot), [print-buddy-frontend](https://github.com/printbuddy/print-buddy-frontend). This repo owns `docker-compose.yml`, `.env`, and the deploy workflow; it does not build anything from source — it only pulls pre-built images from GHCR.

## How it works

1. Each app repo's CI builds and pushes a Docker image to GitHub Container Registry (`ghcr.io/printbuddy/<repo>`) on every push to `main`, tagged both `:latest` and `:<commit-sha>`.
2. This repo's `docker-compose.yml` references those images directly (`image: ghcr.io/printbuddy/print-buddy-backend:${BACKEND_TAG:-latest}`, etc.) — no `build:` context, so the app repos don't need to be checked out on the deploy host at all.
3. A self-hosted GitHub Actions runner lives on the deploy VM (it has no inbound access, so it can't be pushed to — instead it polls out to GitHub). The `Deploy` workflow in this repo (`.github/workflows/deploy.yml`) runs on that runner on a 5-minute schedule (plus `workflow_dispatch` and on push to this repo's `main`), and just does `docker compose pull && docker compose up -d`.

Net effect: merge to any app repo's `main` → image builds and lands in GHCR within a few minutes → the VM's scheduled tick picks it up within 5 more minutes and restarts only the service(s) whose image actually changed. No manual step required for a normal deploy.

Postgres is **not** part of this stack — it runs as its own long-lived container on the VM, managed separately (own volume, own lifecycle). This compose file joins its existing Docker network (`print-buddy-app_default`, external) so `DB_HOSTNAME=postgres` resolves correctly, but never creates, recreates, or touches that container.

## Layout

This repo does **not** need to sit next to the app repos anymore — it's self-contained. On the VM it lives at `~/print-buddy-app-next/print-buddy-infra` (or wherever you choose), alongside nothing but its own `.env`.

## Setup (one-time, per host)

The automated `Deploy` workflow runs in a GitHub-managed workspace that gets wiped clean (`git clean -ffdx`) on every checkout, so `.env` can't live inside it — it's kept one level up and restored into the workspace at the start of every run:

```bash
mkdir -p ~/deploy-secrets && chmod 700 ~/deploy-secrets
cp .env.example ~/deploy-secrets/print-buddy-infra.env
# fill in every value — see .env.example for what each one is for
chmod 600 ~/deploy-secrets/print-buddy-infra.env
```

For a manual/local run (not through the runner), just `cp` that same file to `.env` in whatever directory you're running `docker compose`/`deploy.sh` from.

## Normal operation

Nothing to do. Push to `main` on backend/bot/frontend, CI builds and pushes the image, the runner's scheduled `Deploy` workflow pulls it within 5 minutes.

To force an immediate deploy instead of waiting for the schedule:
- From GitHub: Actions tab → `Deploy` workflow (in this repo) → **Run workflow**.
- From the VM directly: `./deploy.sh`

```
Usage: ./deploy.sh [OPTIONS]

  -s, --service [name]    Service to deploy (frontend, backend, bot, all). Default: all
  -b, --bump [type]       Version bump type (major, minor, fix).
  -h, --help              Show this help message.
```

## Rollback

Every image is pushed as both `:latest` and `:<commit-sha>`, so any past commit on an app repo's `main` is a valid rollback target (as long as GHCR hasn't garbage-collected it).

**One-shot** (reverts on the next scheduled deploy tick):
```bash
./rollback.sh backend a1b2c3d
```

**Sticky** (stays until you undo it): add e.g. `BACKEND_TAG=a1b2c3d` to `.env`, then `docker compose up -d`. Remove the line and redeploy to go back to tracking `:latest`.

## Runner setup (one-time)

The `Deploy` workflow needs a self-hosted GitHub Actions runner registered against this repo, running on the VM as a service so it survives reboots. From this repo's GitHub Settings → Actions → Runners → "New self-hosted runner", follow the Linux x64 instructions, and run `./svc.sh install && ./svc.sh start` at the end so it runs unattended.

## Required one-time GitHub setup

- The 3 GHCR packages (`print-buddy-backend`, `print-bot`, `print-buddy-frontend`) need to be set to **public** visibility (Package settings → Change visibility) so the VM's runner can pull them without needing a registry login/PAT.
- The frontend repo needs 3 repository variables set (Settings → Secrets and variables → Actions → Variables), since Vite bakes these in at CI build time: `VITE_API_BASE_URL`, `VITE_CONTACT_NAME`, `VITE_CONTACT_NUMBER`.

## Why Postgres isn't in this file

The database is a pre-existing, already-running container with real production data and its own volume. Recreating it from this compose file would risk that data on every `docker compose up`. Instead this stack only defines `backend`/`bot`/`frontend` and joins Postgres's network externally — see the comment in `docker-compose.yml`.
