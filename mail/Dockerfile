# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

# Postfix hands outbound mail to two milters: opendkim signs it, opendmarc
# stamps the result. Everything is driven from the environment at boot — see
# entrypoint.sh — so the image itself carries no domain or key material.
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        postfix \
        postfix-pcre \
        opendkim \
        opendkim-tools \
        opendmarc \
        supervisor \
        rsyslog \
        ca-certificates \
        netcat-openbsd; \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY rsyslog.conf /etc/rsyslog.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

# Not published in compose: reachable only from the forum over the internal
# network. An MTA on a public port is an invitation.
EXPOSE 25

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
