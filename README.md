# colors-redirect

A tiny Caddy container that permanently redirects all traffic to `https://www.getcolors.ai` by default, preserving the request path and query string.

It fronts the apex and legacy hostnames for the `getcolors.ai` deployment, so there is no application code here — just the redirect config and its build/deploy pipeline.

## Behavior

| Request | Response |
| --- | --- |
| `GET /up` | `200 OK`, `text/plain`, body `OK` — health check |
| anything else | `301` to `https://www.getcolors.ai{uri}` |

The server listens on plain HTTP on port 80. TLS is terminated by the host proxy in front of it, which is why `auto_https` is off and the server is restricted to HTTP/1.1.

Set `REDIRECT_HOST` to override the destination hostname. It defaults to
`www.getcolors.ai`; supply only a hostname, without a scheme, path, or trailing
slash. Redirects always use HTTPS, and `/up` remains the health endpoint.
Caddy reads the variable at startup, so restart the container after changing it.

```sh
docker run --rm -p 8080:80 -e REDIRECT_HOST=www.example.com colors-redirect
```

## Layout

| File | Purpose |
| --- | --- |
| `Caddyfile` | The redirect and health-check rules |
| `Procfile` | Process list, run by [Hivemind](https://github.com/DarthSim/hivemind) |
| `Dockerfile` | Fetches Hivemind, layers it onto `caddy:2-alpine` |
| `.github/workflows/cicd.yml` | Build, publish to GHCR, deploy |

## Local development

Validate the config after editing:

```sh
caddy validate --config Caddyfile --adapter caddyfile
```

Build and run the image, mapping host port 8080 to the container's port 80:

```sh
docker build -t colors-redirect .
docker run --rm -p 8080:80 colors-redirect
```

Check both paths:

```sh
curl -i http://localhost:8080/up
curl -i http://localhost:8080/foo?bar=1
```

## Deployment

Pushing to `main` (or running the workflow manually) triggers `.github/workflows/cicd.yml`:

1. `arm64` and `amd64` images build natively in parallel and push by digest to `ghcr.io/getcolors/colors-redirect`. Each build uploads its digest as a workflow artifact.
2. A combined `publish-deploy` job acquires a concurrency lock and checks that the run is for the current `main` commit. Older commits and manual runs on other branches skip publication and deployment.
3. The job combines the digests into multi-architecture `:latest` and `:sha-<short-sha>` tags, then connects over SSH while still holding the lock. The key's server-side forced command updates every hostname assigned to this repository by ONCE.

Configure the GitHub environment `once-colors` with:

| Type | Name | Purpose |
| --- | --- | --- |
| Secret | `SSH_PRIVATE_KEY` | ONCE deployment key |
| Variable | `SERVER_IP` | Server address |
| Variable | `SERVER_USER` | SSH user |
| Variable | `SSH_KNOWN_HOSTS` | Host key entry pinned by ONCE for that address |

ONCE publishes these deployment settings during provisioning. The workflow refuses
to connect without `SSH_KNOWN_HOSTS` and enforces strict host-key checking.
