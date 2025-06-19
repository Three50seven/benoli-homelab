FROM alpine:3.20

RUN apk add --no-cache bash curl docker-cli grep coreutils gettext && \
    curl -sLo /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic

WORKDIR /app

COPY backup.cron backup.cron
COPY scripts/ ./scripts/
COPY entrypoint.sh /app/entrypoint.sh

# Ensure scripts are executable
RUN chmod +x /app/entrypoint.sh
RUN chmod +x ./scripts/*.sh

# Add config directory for storing cron schedule
RUN mkdir -p /app/config

ENTRYPOINT ["/app/entrypoint.sh"]