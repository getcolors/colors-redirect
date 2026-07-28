# Stage 1: Fetch Hivemind
FROM alpine:3 AS hivemind
ARG TARGETARCH
RUN apk add --no-cache curl
RUN curl -sL "https://github.com/DarthSim/hivemind/releases/download/v1.1.0/hivemind-v1.1.0-linux-${TARGETARCH}.gz" \
    | gunzip > /usr/local/bin/hivemind \
    && chmod +x /usr/local/bin/hivemind

# Stage 2: Final Image
FROM caddy:2-alpine

COPY --from=hivemind /usr/local/bin/hivemind /usr/local/bin/hivemind

WORKDIR /srv

COPY Caddyfile Procfile ./

EXPOSE 80

CMD ["hivemind", "Procfile"]
