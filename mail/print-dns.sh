#!/usr/bin/env bash
#
# Prints the DNS records this mail server needs. Run at boot, and available any
# time as `make dns` — the boot banner scrolls away, and these are needed again
# every time the domain or selector changes.
#
set -euo pipefail

: "${MAIL_DOMAIN:?MAIL_DOMAIN is not set}"
: "${DKIM_SELECTOR:=mail}"
: "${MAIL_HOSTNAME:=mail.${MAIL_DOMAIN}}"

txt="/var/lib/opendkim/keys/${MAIL_DOMAIN}/${DKIM_SELECTOR}.txt"

if [ ! -f "$txt" ]; then
    echo "No DKIM key yet for ${MAIL_DOMAIN}. Start the mail service and it is generated." >&2
    exit 1
fi

# opendkim-genkey writes BIND zone format, splitting the value across several
# quoted strings because a single TXT string cannot exceed 255 bytes. Most DNS
# panels want one value and do the splitting themselves, so join it back up.
joined="$(grep -o '"[^"]*"' "$txt" | tr -d '"' | tr -d '\n')"

cat <<BANNER

  ============================================================================
   DNS records for ${MAIL_DOMAIN}

   Without these, mail from this server is unsigned, unauthorised, and will be
   rejected or filed as spam no matter how the container is configured.

   1. SPF — says this host may send for the domain
      name   ${MAIL_DOMAIN}.
      type   TXT
      value  v=spf1 mx a ~all

      Covers only this domain's A and MX records. If mail leaves through a
      relay or another provider, add its include:/ip4: or their mail is
      unauthorised too.

   2. DKIM — the public half of the signing key
      name   ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}.
      type   TXT
      value  ${joined}

   3. DMARC — what receivers should do when 1 and 2 fail
      name   _dmarc.${MAIL_DOMAIN}.
      type   TXT
      value  v=DMARC1; p=none; rua=mailto:postmaster@${MAIL_DOMAIN}

      Start at p=none, which asks for reports and changes nothing. Read them
      for a couple of weeks, then tighten to quarantine and reject.

   Also set reverse DNS (PTR) for this server's public IP to ${MAIL_HOSTNAME},
   with a matching A record. Large receivers check it, and it is set at your
   hosting or ISP, not in your own zone.

   Verify once published:
     dig +short TXT ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
     dig +short TXT _dmarc.${MAIL_DOMAIN}
     dig +short TXT ${MAIL_DOMAIN}

   Raw BIND form: ${txt}
  ============================================================================

BANNER
