# print-buddy-infra

Deployment configuration for the three Print Buddy app repos — [print-buddy](https://github.com/printbuddy/print-buddy) (backend), [print-bot](https://github.com/printbuddy/print-bot), [print-buddy-frontend](https://github.com/printbuddy/print-buddy-frontend). This repo owns `docker-compose.yml`, `.env`, and the deploy scripts; it does not build anything from source — it only pulls pre-built images from GHCR.

## How it works

1. Each app repo's CI builds and pushes a Docker image to GitHub Container Registry (`ghcr.io/printbuddy/<repo>`) on every push to `main`, tagged both `:latest` and `:<commit-sha>`.
2. This repo's `docker-compose.yml` references those images directly (`image: ghcr.io/printbuddy/print-buddy-backend:${BACKEND_TAG:-latest}`, etc.) — no `build:` context, so the app repos don't need to be checked out on the deploy host at all.
3. The deploy VM has no inbound access, so nothing can push a deploy to it. Instead a plain cron job on the VM runs `auto-deploy.sh` every hour. It fast-forwards this repo's checkout if `main` moved, then runs `docker compose pull && docker compose up -d`, which downloads only images whose digest changed in GHCR and recreates only those containers.

Net effect: merge to any app repo's `main` → image builds and lands in GHCR within a few minutes → the VM's next hourly tick picks it up and restarts only the service(s) whose image actually changed. No manual step required for a normal deploy, and no GitHub Actions runner on the VM.

(This replaced an earlier setup where a self-hosted GitHub Actions runner on the VM ran a scheduled `Deploy` workflow. GitHub delayed those schedules by up to ~90 minutes in practice, and whenever the runner was offline every tick queued a job that sat "Waiting for a runner" until it timed out 24 hours later.)

Postgres is **not** part of this stack — it runs as its own long-lived container on the VM, managed separately (own volume, own lifecycle). This compose file joins its existing Docker network (`print-buddy-app_default`, external) so `DB_HOSTNAME=postgres` resolves correctly, but never creates, recreates, or touches that container.

## Layout

This repo does **not** need to sit next to the app repos anymore — it's self-contained. On the VM it's a plain `git clone` at `~/print-buddy-infra` (or wherever you choose), with its `.env` symlinked in from `~/deploy-secrets/`. The compose project name is pinned (`name: print-buddy-infra` in `docker-compose.yml`), so the clone's directory name doesn't matter.

## Setup (one-time, per host)

```bash
# 1. Secrets, kept outside the clone
mkdir -p ~/deploy-secrets && chmod 700 ~/deploy-secrets
cp .env.example ~/deploy-secrets/print-buddy-infra.env
# fill in every value — see .env.example for what each one is for
chmod 600 ~/deploy-secrets/print-buddy-infra.env

# 2. The clone (public repo, so no credentials needed to fetch)
git clone https://github.com/PrintBuddy/print-buddy-infra.git ~/print-buddy-infra
ln -s ~/deploy-secrets/print-buddy-infra.env ~/print-buddy-infra/.env

# 3. Uploads directory (see "Uploaded print files persistence" below)
mkdir -p /home/printowner/print-buddy-uploads

# 4. First deploy by hand, to check everything works
~/print-buddy-infra/auto-deploy.sh

# 5. Hourly cron (crontab -e)
0 * * * * $HOME/print-buddy-infra/auto-deploy.sh >> $HOME/print-buddy-deploy.log 2>&1
```

The cron user needs to be in the `docker` group. Change `0 * * * *` to e.g. `*/10 * * * *` for faster pickup. When nothing changed, a run only asks GHCR for three image digests, so it's cheap at any interval.

### Migrating from the old self-hosted runner

If the VM still has the GitHub Actions runner from the previous setup, remove it so it stops polling: `cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh uninstall`, then delete it under this repo's Settings → Actions → Runners (if it's still listed there). The running containers don't need to be touched. Because the compose project name is pinned, the first `auto-deploy.sh` run adopts them.

## Normal operation

Nothing to do. Push to `main` on backend/bot/frontend, CI builds and pushes the image, and the VM's hourly cron picks it up. Check `~/print-buddy-deploy.log` to see what each tick did.

To force an immediate deploy instead of waiting for the next tick, run `./auto-deploy.sh` on the VM (it also syncs this repo), or `./deploy.sh` to deploy one service or bump the version:

## Cross-repo features (backend + frontend touched together)

**Merge backend first.** The frontend image should never go live before the
backend endpoints/columns it calls exist, or production's frontend will hit
routes the deployed backend doesn't have yet.

```
Usage: ./deploy.sh [OPTIONS]

  -s, --service [name]    Service to deploy (frontend, backend, bot, all). Default: all
  -b, --bump [type]       Version bump type (major, minor, fix).
  -h, --help              Show this help message.
```

## Rollback

Every image is pushed as both `:latest` and `:<commit-sha>`, so any past commit on an app repo's `main` is a valid rollback target (as long as GHCR hasn't garbage-collected it).

**One-shot** (reverts on the next cron deploy tick):
```bash
./rollback.sh backend a1b2c3d
```

**Sticky** (stays until you undo it): add e.g. `BACKEND_TAG=a1b2c3d` to `.env`, then `docker compose up -d`. Remove the line and redeploy to go back to tracking `:latest`.

## Required one-time GitHub setup

- The 3 GHCR packages (`print-buddy-backend`, `print-bot`, `print-buddy-frontend`) need to be set to **public** visibility (Package settings → Change visibility) so the VM can pull them without needing a registry login/PAT.
- The frontend repo needs 3 repository variables set (Settings → Secrets and variables → Actions → Variables), since Vite bakes these in at CI build time: `VITE_API_BASE_URL`, `VITE_CONTACT_NAME`, `VITE_CONTACT_NUMBER`.

## Uploaded print files persistence

The backend's `/app/uploads` directory is bind-mounted to a host path (`UPLOADS_HOST` in `.env`, default `/home/printowner/print-buddy-uploads`) so uploaded print files survive container recreates/redeploys. Before this was added, uploads lived only in the backend container's writable layer and were silently lost on every redeploy — a real gap discovered and fixed 2026-07-23. The host directory must exist and be writable by uid:gid `1000:1000` (the backend image's `appuser`) before starting the stack: `mkdir -p /home/printowner/print-buddy-uploads`. Like `~/deploy-secrets/`, keep it outside the repo clone.

## Why Postgres isn't in this file

The database is a pre-existing, already-running container with real production data and its own volume. Recreating it from this compose file would risk that data on every `docker compose up`. Instead this stack only defines `backend`/`bot`/`frontend` and joins Postgres's network externally — see the comment in `docker-compose.yml`.
