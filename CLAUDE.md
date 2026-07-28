# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-purpose container that 301-redirects all traffic to `https://www.getcolors.ai`, preserving the request URI. There is no application code — the entire repo is four config files (`Caddyfile`, `Procfile`, `Dockerfile`, `.github/workflows/cicd.yml`). It fronts the apex/legacy hostnames for the `getcolors.ai` deployment.

## Commands

```sh
# Validate the Caddy config after any edit
caddy validate --config Caddyfile --adapter caddyfile

# Build and run locally (host :8080 -> container :80)
docker build -t colors-redirect .
docker run --rm -p 8080:80 colors-redirect

# Verify behavior
curl -i http://localhost:8080/up          # -> 200 OK, text/plain
curl -i http://localhost:8080/foo?bar=1   # -> 301 to https://www.getcolors.ai/foo?bar=1
```

There are no tests, linters, or package manifests.

## Architecture notes

**TLS is terminated upstream.** The Caddyfile sets `auto_https off` and restricts `protocols h1`, and the server listens on plain `:80`. The host-level proxy (managed by `once`) handles certificates and HTTP/2+. Do not enable automatic HTTPS or bind :443 inside this container.

**`/up` must stay ahead of the catch-all.** Caddy's `handle` blocks are mutually exclusive and matched most-specific-first, so the health endpoint returns 200 while every other path falls through to `redir ... permanent`. Deployment health checks depend on `/up` never being redirected.

**Hivemind supervises the Procfile** even though only one process (`caddy`) is defined. This keeps the image consistent with the other services in the `colors` deployment; add sidecar processes to `Procfile` rather than changing `CMD`.

## CI/CD

`.github/workflows/cicd.yml` runs on push to `main`:

1. `build` is a two-entry matrix building natively on `ubuntu-24.04-arm` and `ubuntu-24.04` in parallel — no QEMU emulation. Each leg pushes **by digest, under no tag at all**, and uploads its digest as an artifact; each has its own GHA cache scope. `provenance: false` is required for the manifest step to work.
2. `manifest` downloads both digests and creates multi-arch `:latest` and `:sha-<short>` in a single `docker buildx imagetools create`. Both halves therefore always come from the same run — the mutable `:arm` / `:amd` tags this replaced were shared across runs, so two pushes landing close together could leave `:latest` with its arm64 half from one commit and its amd64 half from another, undetected.
3. `deploy` opens one SSH connection and closes it.

### The deploy is a ping

The deploy job does not say what to deploy. Its whole payload is:

```sh
ssh -T -n <user>@<server> deploy-ping
```

and `deploy-ping` is ignored. The deploy key is pinned to a ForceCommand in the
server's `authorized_keys`, so the server runs its own script — babashka, which
reads the host list out of `colors.yml` — and it reconciles **every**
application in the profile: this redirect and `www.getcolors.ai` both.

- **No host, image or application name appears in this repo's CI**, nor in the
  deploy script. `colors.yml` is the single source of truth, so adding an
  application to the deployment does not touch this file.
- **A push here also reconciles the website**, and a failure there turns this
  repo's build red. That is the accepted cost of keeping host names out of CI.
- **The key is no longer an arbitrary-command credential.** With
  `restrict,command="..."`, a leaked `SSH_PRIVATE_KEY` can trigger a deploy of
  already-published images and nothing else.

The script, the `authorized_keys` line and the sudoers entry live in
**`getcolors/colors-website` under `deploy/`** — one copy, because one server
runs both applications. Don't add a second copy here.

Deployment credentials: secret `SSH_PRIVATE_KEY`; variables `SERVER_IP`,
`SERVER_USER`, `SSH_KNOWN_HOSTS`. All are scoped to the **`colors-website`**
GitHub Environment — named after the `colors.yml` profile, not after this repo.
Get that name wrong and every one of them silently resolves to empty.
