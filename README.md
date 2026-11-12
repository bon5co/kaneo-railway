# kaneo-railway

Thin wrapper over `ghcr.io/usekaneo/kaneo` (Kaneo, an open-source project management tool with a REST API, MCP server
and API keys) for the Railway template "Kaneo". Moves the bundled nginx front onto Railway's injected `PORT` (upstream
hard-codes 5173), creates the instance administrator from `ADMIN_EMAIL` and `ADMIN_PASSWORD` before nginx accepts a
sign-up (the sign-up route answers 503 until then) and closes public registration through the instance settings API,
and refuses to start without a stable `AUTH_SECRET`. Needs a PostgreSQL database (`POSTGRES_HOST`, `POSTGRES_USER`,
`POSTGRES_PASSWORD`, `POSTGRES_DB`).
