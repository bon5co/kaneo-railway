# Kaneo for Railway.
#
# Kaneo ships one bundled image: an nginx front (hard-coded to listen on 5173) in front of a Hono API on 127.0.0.1:1337.
# A stock deploy on Railway has three defects. nginx ignores Railway's injected PORT, so the edge and the healthcheck
# dial a port nothing listens on. Registration is open and the first account to register becomes the instance
# administrator, so whoever reaches a fresh deploy first owns it. AUTH_SECRET is regenerated at every start unless set,
# which signs every user out on each redeploy. This wrapper moves nginx onto $PORT, creates the administrator from
# ADMIN_EMAIL and ADMIN_PASSWORD before nginx accepts a sign-up (the sign-up route answers 503 until that is done) and
# then closes registration through the instance settings API. The application is otherwise untouched.
FROM ghcr.io/usekaneo/kaneo:2.49.0@sha256:cd1826b1aba3ce736015cadf6f6c975d923aac00f4b6aaa7aedb29bc722dae49

COPY --chmod=0755 railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chmod=0644 bootstrap.js /usr/local/lib/railway-bootstrap.js

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/kaneo-entrypoint.sh"]
