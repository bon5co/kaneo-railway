#!/bin/sh
# Kaneo for Railway: validate the variables, move nginx onto Railway's PORT, keep sign-up shut until the administrator
# exists, bootstrap that administrator once the API is up, then hand over to the upstream entrypoint.
set -eu

fail() { echo "railway-entrypoint: $*" >&2; exit 1; }

[ -n "${ADMIN_EMAIL:-}" ] || fail "ADMIN_EMAIL is required"
P="${ADMIN_PASSWORD:-}"; [ "${#P}" -ge 12 ] || fail "ADMIN_PASSWORD is required (12 characters or more)"
[ -n "${AUTH_SECRET:-}" ] || fail "AUTH_SECRET is required (a random one per start would sign every user out on each redeploy)"
[ -n "${KANEO_CLIENT_URL:-}" ] || fail "KANEO_CLIENT_URL is required (the public https URL)"

PORT="${PORT:-8080}"
CONF=/etc/nginx/conf.d/default.conf
FLAG=/var/lib/kaneo/tmp/.bootstrapped
mkdir -p /var/lib/kaneo/tmp
rm -f "$FLAG"

# A container restarted in place already carries the patched config; patch only an upstream-pristine one.
if grep -q 'sign-up/email' "$CONF"; then
  sed -i -E "s/listen [0-9]+;/listen ${PORT};/" "$CONF"
else
  grep -q 'listen 5173;' "$CONF" || fail "upstream nginx config no longer says 'listen 5173;'; wrapper needs updating"
  sed -i "s/listen 5173;/listen ${PORT};/" "$CONF"

# Sign-up stays shut (503) until the bootstrap below has created the administrator and closed registration.
BLOCK='    location = /api/auth/sign-up/email {
        if (!-f /var/lib/kaneo/tmp/.bootstrapped) { return 503; }
        proxy_pass http://127.0.0.1:1337;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header CF-Connecting-IP "";
        proxy_set_header X-Kaneo-Client-IP "";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
'
  BLK="$BLOCK" awk '/^    location \/api\/ \{/ && !done { print ENVIRON["BLK"]; done = 1 } { print }' "$CONF" > "$CONF.new"
  grep -q 'sign-up/email' "$CONF.new" || fail "could not insert the sign-up guard into the nginx config"
  cat "$CONF.new" > "$CONF"
  rm -f "$CONF.new"
fi

# Bootstrap in the background; the API starts under the upstream entrypoint. If it fails, take the container down
# (restart policy brings it back) rather than run with registration open.
(
  if ! node /usr/local/lib/railway-bootstrap.js; then
    echo "railway-entrypoint: bootstrap failed, stopping the container" >&2
    kill -TERM 1
  fi
) &

echo "railway-entrypoint: uid=$(id -u) port=$PORT client_url=$KANEO_CLIENT_URL"
exec docker-entrypoint.sh "$@"
