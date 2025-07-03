FROM alpine:3.20

RUN apk add --no-cache bash curl docker-cli openssh-client grep tzdata tini && \
    curl -sLo /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic

WORKDIR /app

COPY zfs-backup.cron zfs-backup.cron
COPY scripts/ ./scripts/
COPY entrypoint.sh /app/entrypoint.sh
COPY known_hosts /root/.ssh/known_hosts

# Ensure scripts are executable
RUN chmod +x /app/entrypoint.sh
RUN chmod +x ./scripts/*.sh

# Add proper file permissions to check known_hosts for SSH:
RUN chmod 644 /root/.ssh/known_hosts

# Add config directory for storing cron schedule
RUN mkdir -p /app/config

# Create environment variable for the supercronic crontab schedule and heartbeat log
ENV CRON_FILE=/app/config/zfs-backup.cron
ENV HEARTBEAT_LOG=/tmp/heartbeat.log

ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]