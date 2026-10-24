# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-purpose container that 301-redirects all traffic to `https://www.getcolors.ai` by default, preserving the request URI. `REDIRECT_HOST` overrides the hostname at startup; its default is `www.getcolors.ai`. The value must be a hostname without a scheme, path, or trailing slash; HTTPS remains fixed. There is no application code — the entire repo is four config files (`Caddyfile`, `Procfile`, `Dockerfile`, `.github/workflows/cicd.yml`). It fronts the apex/legacy hostnames for the `getcolors.ai` deployment.

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

**TLS is terminated upstream.** The Caddyfile sets `auto_https off` and restricts `protocols h1`, and the server listens on plain `:80`. The host-level ONCE proxy handles certificates and HTTP/2+. Do not enable automatic HTTPS or bind :443 inside this container.

**`/up` must stay ahead of the catch-all.** Caddy's `handle` blocks are mutually exclusive and matched most-specific-first, so the health endpoint returns 200 while every other path falls through to `redir ... permanent`. Deployment health checks depend on `/up` never being redirected.

**Hivemind supervises the Procfile** even though only one process (`caddy`) is defined. This keeps the image consistent with the other services in the `colors` deployment; add sidecar processes to `Procfile` rather than changing `CMD`.

## CI/CD

`.github/workflows/cicd.yml` runs on pushes to `main` and manual dispatch:

1. The `build` matrix builds natively on `ubuntu-24.04-arm` / `ubuntu-24.04` in parallel, pushes images by digest, and uploads per-architecture digest artifacts. Each architecture has its own GHA cache scope; `provenance: false` keeps the digest inputs as single-platform images.
2. `publish` holds the `publish-colors-redirect` concurrency lock without cancelling an active run. Immediately before publishing, it checks the current `main` SHA through the GitHub API. Stale commits and runs on other branches skip publication.
3. `docker buildx imagetools create` combines this run's digests into multi-architecture `:latest` and `:sha-<short>` tags.

Publishing does not deploy. The `pocketdeploy-v2` deployment pins this image by
digest for `getcolors.ai`, `bigconfig.ai`, `www.bigconfig.ai` and
`marketplace.bigconfig.ai`; PocketDeploy supports GitHub delivery for one
application per repository. Roll out a new image by updating the digest there and
running `pocketdeploy converge`.

## Documentation

`index.html` is this repository's landing page and carries two analytics tags: GA4 measurement ID `G-4VKP1WY4QJ`, whose explicit `page_title` must exactly equal the decoded HTML `<title>` and stay distinct and stable so one Analytics property can separate repositories, and the self-hosted Rybbit snippet `<script src="https://rybbit.getcolors.ai/api/script.js" data-site-id="9fb9c41a6d49" defer></script>`, which shares one site ID across every page because `getcolors.github.io/<repo>/` paths already encode the repository. Never add one tag without the other.
