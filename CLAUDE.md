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

1. `build-arm` and `build-amd` build natively on `ubuntu-24.04-arm` / `ubuntu-24.04` in parallel — no QEMU emulation — pushing per-arch tags (`:arm`, `:amd`, `:sha-<short>-<arch>`) to `ghcr.io/<repo>`. Each uses a separate GHA cache scope.
2. `manifest` stitches the per-arch tags into multi-arch `:latest` and `:sha-<short>` with `docker manifest create/annotate/push`. `provenance: false` in the build steps is required for this manual manifest approach to work.
3. `deploy` SSHes to the server and runs `sudo once update getcolors.ai`.

Because the arch-specific tags are the build inputs to the manifest step, changing a tag name in one build job requires updating the manifest job to match.

Deployment secrets: `SSH_PRIVATE_KEY`, `SERVER_IP`, `SERVER_USER`.
