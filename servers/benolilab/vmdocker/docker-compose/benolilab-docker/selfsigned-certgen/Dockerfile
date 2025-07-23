FROM alpine:3.20

RUN apk add --no-cache bash curl jq openssl grep tzdata tini && \
    curl -sLo /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic

WORKDIR /app

COPY selfsigned-certgen.cron selfsigned-certgen.cron
COPY scripts/ ./scripts/
COPY entrypoint.sh /app/entrypoint.sh

# Ensure scripts are executable
RUN chmod +x /app/entrypoint.sh
RUN chmod +x ./scripts/*.sh

# Add config directory for storing cron schedule
RUN mkdir -p /app/config

# Create environment variable for the supercronic crontab schedule and heartbeat log
ENV CRON_FILE=/app/config/selfsigned-certgen.cron
ENV HEARTBEAT_LOG=/tmp/heartbeat.log

ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]