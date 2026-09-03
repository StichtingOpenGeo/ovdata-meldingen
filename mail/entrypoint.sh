#!/usr/bin/env bash
#
# Configures postfix, opendkim and opendmarc from the environment on every
# boot, generating a DKIM keypair the first time. The keypair lives on a
# volume: regenerating it would invalidate the DNS record you published.
#
set -euo pipefail

: "${MAIL_DOMAIN:?set MAIL_DOMAIN to the domain the forum sends from, e.g. example.org}"
: "${MAIL_HOSTNAME:=mail.${MAIL_DOMAIN}}"
: "${DKIM_SELECTOR:=mail}"
: "${DKIM_KEY_BITS:=2048}"
# Empty means deliver straight to each recipient's MX. See the README on why
# that usually does not work from a home or office connection.
: "${MAIL_RELAYHOST:=}"
: "${MAIL_RELAY_USER:=}"
: "${MAIL_RELAY_PASS:=}"
# Which clients may send through this MTA. The compose network only.
: "${MAIL_MYNETWORKS:=127.0.0.0/8 [::1]/128 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8}"

KEYDIR="/var/lib/opendkim/keys/${MAIL_DOMAIN}"
PRIVATE="${KEYDIR}/${DKIM_SELECTOR}.private"

log() { printf '[mail] %s\n' "$*"; }

# --- DKIM keypair ------------------------------------------------------------
if [ ! -f "$PRIVATE" ]; then
    log "generating a ${DKIM_KEY_BITS}-bit DKIM key for ${MAIL_DOMAIN} (selector ${DKIM_SELECTOR})"
    mkdir -p "$KEYDIR"
    opendkim-genkey -b "$DKIM_KEY_BITS" -d "$MAIL_DOMAIN" -D "$KEYDIR" -s "$DKIM_SELECTOR" -v
    chown -R opendkim:opendkim /var/lib/opendkim
    chmod 600 "$PRIVATE"
else
    log "reusing the existing DKIM key at ${PRIVATE}"
fi
chown -R opendkim:opendkim /var/lib/opendkim

# --- opendkim ----------------------------------------------------------------
cat > /etc/opendkim.conf <<CONF
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
UMask                   007
Mode                    sv
Canonicalization        relaxed/simple
OversignHeaders         From
Socket                  inet:8891@127.0.0.1
PidFile                 /run/opendkim/opendkim.pid
UserID                  opendkim
KeyTable                /etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
InternalHosts           /etc/opendkim/TrustedHosts
ExternalIgnoreList      /etc/opendkim/TrustedHosts
CONF

mkdir -p /etc/opendkim /run/opendkim
echo "${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN} ${MAIL_DOMAIN}:${DKIM_SELECTOR}:${PRIVATE}" \
    > /etc/opendkim/KeyTable
echo "*@${MAIL_DOMAIN} ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}" \
    > /etc/opendkim/SigningTable
{ echo "127.0.0.1"; echo "::1"; echo "localhost"; for n in $MAIL_MYNETWORKS; do echo "$n"; done; } \
    > /etc/opendkim/TrustedHosts
chown -R opendkim:opendkim /etc/opendkim /run/opendkim

# --- opendmarc ---------------------------------------------------------------
# DMARC is a *receiver-side* check: it validates that inbound mail's SPF or
# DKIM aligns with its From domain. On a send-only MTA it has nothing to
# verify, so it is here to stamp Authentication-Results and to be ready if this
# host ever accepts inbound mail. It does not make outbound mail more
# deliverable — the DMARC DNS record below does that.
cat > /etc/opendmarc.conf <<CONF
Syslog                  true
UMask                   0002
Socket                  inet:8893@127.0.0.1
PidFile                 /run/opendmarc/opendmarc.pid
UserID                  opendmarc:opendmarc
IgnoreAuthenticatedClients true
RejectFailures          false
TrustedAuthservIDs      ${MAIL_HOSTNAME}
AuthservID              ${MAIL_HOSTNAME}
HistoryFile             /var/lib/opendmarc/opendmarc.dat
CONF
mkdir -p /run/opendmarc /var/lib/opendmarc
chown -R opendmarc:opendmarc /run/opendmarc /var/lib/opendmarc

# --- postfix -----------------------------------------------------------------
postconf -e "myhostname = ${MAIL_HOSTNAME}"
postconf -e "mydomain = ${MAIL_DOMAIN}"
postconf -e "myorigin = \$mydomain"
postconf -e "mydestination = localhost"
postconf -e "mynetworks = ${MAIL_MYNETWORKS}"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"

# Not an open relay: accept only from our own network, and refuse to forward
# for anyone else. These two lines are the difference between a mail server and
# a spam cannon.
postconf -e "smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"

# Postfix 3.4+ can log straight to stdout, so the container needs no syslog
# plumbing of its own for postfix itself.
postconf -e "maillog_file = /dev/stdout"

# Debian ships every postfix daemon chrooted into /var/spool/postfix. The
# container is already the jail, and inside the chroot there is no
# /etc/resolv.conf or /etc/hosts — so cleanup(8) cannot resolve "localhost" and
# silently fails to reach the milters, sending mail out unsigned. Turn it off
# for every service, and address the milters by IP so nothing depends on
# name resolution at all.
postconf -F '*/*/chroot = n'

postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = inet:127.0.0.1:8891, inet:127.0.0.1:8893"
postconf -e "non_smtpd_milters = \$smtpd_milters"

postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_CApath = /etc/ssl/certs"
postconf -e "smtpd_tls_security_level = none"

postconf -e "message_size_limit = 20480000"
postconf -e "biff = no"
postconf -e "append_dot_mydomain = no"
postconf -e "compatibility_level = 3.6"

if [ -n "$MAIL_RELAYHOST" ]; then
    log "relaying through ${MAIL_RELAYHOST}"
    postconf -e "relayhost = ${MAIL_RELAYHOST}"
    if [ -n "$MAIL_RELAY_USER" ]; then
        printf '%s %s:%s\n' "$MAIL_RELAYHOST" "$MAIL_RELAY_USER" "$MAIL_RELAY_PASS" \
            > /etc/postfix/sasl_passwd
        chmod 600 /etc/postfix/sasl_passwd
        postmap /etc/postfix/sasl_passwd
        postconf -e "smtp_sasl_auth_enable = yes"
        postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
        postconf -e "smtp_sasl_security_options = noanonymous"
        postconf -e "smtp_tls_security_level = encrypt"
    fi
else
    postconf -e "relayhost ="
    log "no MAIL_RELAYHOST set — delivering directly to recipient MX servers"
fi

newaliases 2>/dev/null || true

# --- the DNS records that make any of this work ------------------------------
# Same output as "make dns", so there is one place this is ever formatted.
mail-dns || true

log "starting: $*"
exec "$@"
