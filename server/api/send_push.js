/**
 * Send an APNs push when a reaction row is inserted.
 *
 * Invoked via a Supabase Database Webhook on `reactions` INSERT. Incoming
 * payload shape (Supabase standard):
 *   {
 *     type: "INSERT",
 *     table: "reactions",
 *     schema: "public",
 *     record: { id, challenge_id, from_user, to_user, emoji, created_at },
 *     old_record: null
 *   }
 *
 * Responsibilities:
 *   1. Verify the shared secret header so only Supabase can call us
 *   2. Look up the recipient's APNs token + the sender's display info
 *   3. Sign an ES256 JWT for APNs (spec: https://developer.apple.com/documentation/usernotifications/establishing_a_token-based_connection_to_apns)
 *   4. POST to APNs via HTTP/2 with the alert payload
 *
 * Env vars required in Vercel:
 *   - SUPABASE_URL                 (https://zduiktztdlgsahpteicc.supabase.co)
 *   - SUPABASE_SERVICE_ROLE_KEY    (from Supabase dashboard → Settings → API)
 *   - APNS_TEAM_ID                 (XB6YUT7453)
 *   - APNS_KEY_ID                  (10-char ID of the APNs key created in Apple portal)
 *   - APNS_PRIVATE_KEY             (full .p8 contents incl. BEGIN/END)
 *   - APNS_BUNDLE_ID               (com.nodecompass.app)
 *   - SUPABASE_WEBHOOK_SECRET      (any random string, used to auth incoming webhook)
 */

const crypto = require("crypto");
const http2 = require("http2");

const ENV = {
  supabaseUrl:            process.env.SUPABASE_URL,
  serviceRoleKey:         process.env.SUPABASE_SERVICE_ROLE_KEY,
  apnsTeamId:             process.env.APNS_TEAM_ID,
  apnsKeyId:              process.env.APNS_KEY_ID,
  apnsPrivateKey:         process.env.APNS_PRIVATE_KEY,
  apnsBundleId:           process.env.APNS_BUNDLE_ID || "com.nodecompass.app",
  webhookSecret:          process.env.SUPABASE_WEBHOOK_SECRET,
};

module.exports = async (req, res) => {
  // ── 1. Only POST
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  // ── 2. Verify shared secret (Supabase webhook adds this via custom header)
  const provided = req.headers["x-webhook-secret"] || req.headers["X-Webhook-Secret"];
  if (!ENV.webhookSecret) {
    return res.status(500).json({ error: "Server missing SUPABASE_WEBHOOK_SECRET" });
  }
  if (provided !== ENV.webhookSecret) {
    return res.status(401).json({ error: "Invalid webhook secret" });
  }

  // ── 3. Parse webhook body
  // Vercel may pass body as string or parsed object depending on runtime
  let body = req.body;
  if (typeof body === "string") {
    try { body = JSON.parse(body); } catch { return res.status(400).json({ error: "Bad JSON" }); }
  }
  const record = body && body.record;
  if (!record || body.type !== "INSERT" || body.table !== "reactions") {
    return res.status(200).json({ skipped: "not a reactions INSERT" });
  }

  const { from_user, to_user, emoji, challenge_id } = record;
  if (!from_user || !to_user || !emoji) {
    return res.status(400).json({ error: "Missing fields on record" });
  }

  try {
    // ── 4. Look up recipient's device token + sender's display info in parallel
    const [deviceRow, senderRow, challengeRow] = await Promise.all([
      supabaseGetOne(`user_devices?anon_user_id=eq.${to_user}&select=apns_token,apns_env`),
      supabaseGetOne(`profiles?anon_user_id=eq.${from_user}&select=display_name,avatar_emoji`),
      supabaseGetOne(`circle_challenges?id=eq.${challenge_id}&select=title`),
    ]);

    if (!deviceRow) {
      // Recipient has never registered — nothing to push to. Not an error.
      return res.status(200).json({ skipped: "no device for recipient" });
    }

    const senderName = (senderRow && senderRow.display_name) || "Someone";
    const challengeTitle = (challengeRow && challengeRow.title) || "your challenge";

    // ── 5. Sign APNs JWT
    const jwtToken = signApnsJwt({
      teamId: ENV.apnsTeamId,
      keyId: ENV.apnsKeyId,
      privateKeyPem: ENV.apnsPrivateKey,
    });

    // ── 6. Construct alert payload
    const payload = {
      aps: {
        alert: {
          title: `${emoji} from ${senderName}`,
          body: `on your "${challengeTitle}"`,
        },
        badge: 1,
        sound: "default",
        category: "REACTION",
      },
      // Custom data for in-app routing.
      reaction_id: record.id,
      challenge_id: record.challenge_id,
    };

    // ── 7. Send
    const result = await sendApnsPush({
      deviceToken: deviceRow.apns_token,
      env: deviceRow.apns_env,
      jwtToken,
      bundleId: ENV.apnsBundleId,
      payload,
    });

    return res.status(200).json({
      sent: true,
      apnsStatus: result.statusCode,
      apnsBody: result.body || null,
    });
  } catch (err) {
    // Diagnostic: include a SAFE preview of the env var shape so we can see
    // what format the key arrived in. Only first 30 + last 30 chars +
    // length — never the full key.
    const k = ENV.apnsPrivateKey || "";
    const preview = k
      ? `${k.slice(0, 30)}...${k.slice(-30)} (len=${k.length}, hasEscapedN=${k.includes("\\n")}, hasNL=${k.includes("\n")}, hasCR=${k.includes("\r")})`
      : "MISSING";
    return res.status(500).json({
      error: String(err.message || err),
      key_preview: preview,
    });
  }
};

// ─────────────────────── Supabase REST helper ────────────────────────

async function supabaseGetOne(path) {
  const url = `${ENV.supabaseUrl}/rest/v1/${path}`;
  const response = await fetch(url, {
    headers: {
      apikey: ENV.serviceRoleKey,
      Authorization: `Bearer ${ENV.serviceRoleKey}`,
      // Ask PostgREST to return a single object (or 406 if 0/2+)
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    throw new Error(`Supabase ${response.status}: ${await response.text()}`);
  }
  const rows = await response.json();
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

// ─────────────────────── APNs JWT signing (ES256) ───────────────────

/**
 * Sign a JWT using ES256 for APNs provider auth. Spec: the signature
 * must be raw r||s (64 bytes), not DER — Apple rejects the latter. Node's
 * crypto.sign produces DER by default; we request ieee-p1363 to get raw.
 */
function signApnsJwt({ teamId, keyId, privateKeyPem }) {
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: teamId, iat: Math.floor(Date.now() / 1000) };

  const headerB64 = b64url(Buffer.from(JSON.stringify(header)));
  const payloadB64 = b64url(Buffer.from(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  // Reconstruct a valid PEM from whatever shape Vercel stored the value as.
  // Three cases observed in the wild:
  //   1. Real newlines preserved → already valid, just trim
  //   2. Literal `\n` escape sequences → unescape
  //   3. Single-line, spaces-where-newlines-should-be (Vercel's default
  //      multiline-paste handling) → pull BEGIN/END markers out and rejoin
  //      the base64 body with real newlines
  const normalizedKey = (() => {
    let s = (privateKeyPem || "").trim()
      .replace(/\\n/g, "\n")
      .replace(/\r\n/g, "\n");
    if (s.includes("\n")) return s;            // case 1 or 2 — already valid

    // Case 3: single-line string. Extract BEGIN/END markers, rejoin body
    // (which is space-separated base64 chunks) with newlines.
    const begin = s.match(/-----BEGIN [A-Z ]+-----/);
    const end   = s.match(/-----END [A-Z ]+-----/);
    if (!begin || !end) return s;              // not a PEM at all — let crypto throw
    const bodyStart = s.indexOf(begin[0]) + begin[0].length;
    const bodyEnd   = s.indexOf(end[0]);
    const body = s.slice(bodyStart, bodyEnd).trim().replace(/\s+/g, "\n");
    return `${begin[0]}\n${body}\n${end[0]}`;
  })();

  const signer = crypto.createSign("SHA256");
  signer.update(signingInput);
  const signature = signer.sign({
    key: normalizedKey,
    format: "pem",
    dsaEncoding: "ieee-p1363",
  });

  return `${signingInput}.${b64url(signature)}`;
}

function b64url(buf) {
  return buf.toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

// ─────────────────────── APNs HTTP/2 send ───────────────────────────

function sendApnsPush({ deviceToken, env, jwtToken, bundleId, payload }) {
  return new Promise((resolve, reject) => {
    const host = env === "production"
      ? "https://api.push.apple.com:443"
      : "https://api.sandbox.push.apple.com:443";

    const client = http2.connect(host);
    const reqStream = client.request({
      ":method":         "POST",
      ":path":           `/3/device/${deviceToken}`,
      authorization:     `bearer ${jwtToken}`,
      "apns-topic":      bundleId,
      "apns-priority":   "10",
      "apns-push-type":  "alert",
      "content-type":    "application/json",
    });

    let statusCode = 0;
    let body = "";
    const timeout = setTimeout(() => {
      reqStream.close();
      client.close();
      reject(new Error("APNs request timeout"));
    }, 10_000);

    reqStream.on("response", (headers) => {
      statusCode = headers[":status"];
    });
    reqStream.on("data", (chunk) => { body += chunk.toString(); });
    reqStream.on("end", () => {
      clearTimeout(timeout);
      client.close();
      resolve({ statusCode, body });
    });
    reqStream.on("error", (err) => {
      clearTimeout(timeout);
      client.close();
      reject(err);
    });
    client.on("error", reject);

    reqStream.write(JSON.stringify(payload));
    reqStream.end();
  });
}
