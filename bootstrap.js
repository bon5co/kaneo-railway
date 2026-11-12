// Creates the Kaneo instance administrator from ADMIN_EMAIL / ADMIN_PASSWORD and closes public registration.
// Talks to the API on loopback, so nothing external can race it: nginx answers 503 on sign-up until the flag
// file written at the end exists. Idempotent: later boots only sign in and re-assert the registration policy.
const fs = require("node:fs");

const BASE = "http://127.0.0.1:1337/api";
const FLAG = "/var/lib/kaneo/tmp/.bootstrapped";
const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const keepOpen = process.env.ALLOW_REGISTRATION === "true";
// Node's fetch sends Sec-Fetch-Mode, which makes better-auth treat the call as a browser request and demand an Origin.
const json = { "Content-Type": "application/json", Origin: new URL(process.env.KANEO_CLIENT_URL).origin };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (m) => console.log(`bootstrap: ${m}`);

async function waitForApi() {
  for (let i = 0; i < 1200; i++) {
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) return;
    } catch {}
    await sleep(250);
  }
  throw new Error("API did not become healthy within 300s");
}

async function signIn() {
  const r = await fetch(`${BASE}/auth/sign-in/email`, {
    method: "POST",
    headers: json,
    body: JSON.stringify({ email, password }),
  });
  if (!r.ok) return { status: r.status, token: null };
  return { status: r.status, token: r.headers.get("set-auth-token") };
}

async function main() {
  await waitForApi();
  let { token } = await signIn();
  if (!token) {
    const r = await fetch(`${BASE}/auth/sign-up/email`, {
      method: "POST",
      headers: json,
      body: JSON.stringify({ email, password, name: "admin" }),
    });
    const body = await r.text();
    if (r.ok) {
      log("administrator created");
      ({ token } = await signIn());
    } else if (body.includes("REGISTRATION_NOT_ALLOWED")) {
      // Registration is already closed: an earlier boot created the administrator, whose password may since have
      // been changed in the app. Nothing to enforce without a session.
      log("registration already closed and the configured login is not valid; leaving settings as they are");
      fs.writeFileSync(FLAG, "");
      return;
    } else {
      throw new Error(`sign-up answered ${r.status}: ${body.slice(0, 200)}`);
    }
  }
  if (!token) throw new Error("could not obtain a session for the administrator");

  const auth = { ...json, Authorization: `Bearer ${token}` };
  const s = await fetch(`${BASE}/admin/settings`, { headers: auth });
  if (!s.ok) throw new Error(`settings read answered ${s.status}; the account is not the instance administrator`);
  const settings = await s.json();
  if (settings.registrationEnabled && !keepOpen) {
    const p = await fetch(`${BASE}/admin/settings`, {
      method: "PATCH",
      headers: auth,
      body: JSON.stringify({ registrationEnabled: false }),
    });
    if (!p.ok) throw new Error(`closing registration answered ${p.status}`);
    log("registration closed");
  } else {
    log(`registration left ${settings.registrationEnabled ? "open (ALLOW_REGISTRATION=true)" : "closed"}`);
  }
  fs.writeFileSync(FLAG, "");
  log("done");
}

main().catch((e) => {
  console.error(`bootstrap: ${e.message}`);
  process.exit(1);
});
