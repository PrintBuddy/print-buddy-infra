# Print Buddy E2E suite

Playwright tests exercising the real cross-service user journeys (login,
print submission, refunds, admin) against an ephemeral stack: a throwaway
Postgres, a CUPS sidecar with only a virtual `PDF` printer (no physical
printer is ever reachable from here), and the backend/frontend images
under test.

This runs as a required PR check on the `backend` and `frontend` repos —
see their `.github/workflows/ci.yml` `e2e` job. It intentionally does not
include the bot service: bot has no browser-drivable UI, and its own
unit/service-layer tests remain its safety net.

## Why the frontend image must always be built fresh for E2E

`VITE_API_BASE_URL` is baked into the frontend's static JS at **build**
time (see `frontend/app/src/services/api.js`'s `axios.create({ baseURL:
import.meta.env.VITE_API_BASE_URL })` — every request goes to that
absolute URL, not a relative path nginx could proxy at runtime). The
published `:latest` frontend image was built with the real production
URL, so it can't be reused as-is here: this stack always builds the
frontend locally (from whichever ref is under test) with
`VITE_API_BASE_URL=http://localhost:8000/api` — the backend's *host-published*
port, since Playwright's browser runs on the CI runner itself, not inside
this compose network, and can't resolve service names like `backend`.

Backend has no equivalent build-time baking (config is read from env vars
at runtime), so its CI can just pull the other repo's already-published
`:latest` image when backend isn't the repo under test.

## Running locally

```sh
# From this directory:
docker compose -f docker-compose.e2e.yml build
BACKEND_IMAGE=<local-or-ghcr-backend-image> \
FRONTEND_IMAGE=<local-frontend-image-built-with-the-VITE_API_BASE_URL-above> \
  docker compose -f docker-compose.e2e.yml up -d

python3 seed.py

npm install
npx playwright test

docker compose -f docker-compose.e2e.yml down -v
```

This has not yet been run end-to-end in a real Docker environment (built
and reviewed without Docker access) — treat the CUPS sidecar's printer
auto-registration and the Playwright selectors as the highest-risk,
least-verified parts, and do a real dry run before relying on this as a
merge-blocking gate.
