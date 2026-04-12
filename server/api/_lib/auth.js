/**
 * Shared authentication + security middleware for Vercel serverless functions.
 *
 * Provides:
 *   - API key authentication (X-API-Key header) for app endpoints
 *   - Plaid webhook signature verification (HMAC-SHA256)
 *   - CORS origin restriction
 *   - Simple in-memory rate limiting
 *
 * Usage:
 *   const { requireApiKey, verifyPlaidWebhook, corsHeaders, rateLimit } = require("./_lib/auth");
 *   module.exports = async (req, res) => {
 *     if (!rateLimit(req, res)) return;
 *     corsHeaders(res);
 *     if (!requireApiKey(req, res)) return;
 *     // ... handler logic
 *   };
 */

const crypto = require("crypto");

// ───────────────────────── CORS ─────────────────────────

/**
 * Apply CORS headers. Restricts origins when CORS_ORIGINS env var is set.
 */
function corsHeaders(res, allowedMethods = "GET, POST, OPTIONS") {
  const allowedOrigins = process.env.CORS_ORIGINS;
  res.setHeader("Access-Control-Allow-Origin", allowedOrigins || "*");
  res.setHeader("Access-Control-Allow-Methods", allowedMethods);
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, X-API-Key");
}

// ─────────────────── API Key Auth ────────────────────

/**
 * Require a valid X-API-Key header. If API_KEY env var is not set (dev mode),
 * this is a no-op. Returns true if request should proceed, false if it sent
 * an error response.
 */
function requireApiKey(req, res) {
  const expected = process.env.API_KEY;
  if (!expected) return true; // Dev mode: no auth

  const provided = req.headers["x-api-key"];
  if (!provided || provided !== expected) {
    res.status(401).json({ error: "Unauthorized: invalid or missing API key" });
    return false;
  }
  return true;
}

// ─────────────── Webhook Signature ───────────────

/**
 * Verify a Plaid webhook signature using HMAC-SHA256.
 * Only enforced when PLAID_WEBHOOK_SECRET env var is set.
 * Returns true if verified (or if verification is disabled), false if rejected.
 */
function verifyPlaidWebhook(req, res) {
  const secret = process.env.PLAID_WEBHOOK_SECRET;
  if (!secret) return true; // Verification disabled

  const signature = req.headers["plaid-verification"];
  if (!signature) {
    res.status(401).json({ error: "Missing webhook signature" });
    return false;
  }

  try {
    // Vercel pre-parses JSON bodies, so we need to re-stringify deterministically.
    // For production-grade verification, configure Vercel to send raw body.
    const body = typeof req.body === "string" ? req.body : JSON.stringify(req.body);
    const expectedSignature = crypto
      .createHmac("sha256", secret)
      .update(body)
      .digest("hex");

    if (signature !== expectedSignature) {
      res.status(401).json({ error: "Invalid webhook signature" });
      return false;
    }
    return true;
  } catch (e) {
    console.error("[auth] Webhook verification error:", e.message);
    res.status(500).json({ error: "Signature verification failed" });
    return false;
  }
}

// ───────────────── Rate Limiting ─────────────────

// In-memory rate limit map. Persists across warm invocations of the same
// Vercel instance; cold starts reset the map, which is acceptable for
// a personal-use app.
const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 60;           // 60 requests/minute per IP

/**
 * Enforces a simple per-IP rate limit. Returns true if the request may
 * proceed, false if it sent a 429.
 */
function rateLimit(req, res) {
  const key = req.headers["x-forwarded-for"] || req.connection?.remoteAddress || "unknown";
  const now = Date.now();
  const entry = rateLimitMap.get(key) || { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };

  if (now > entry.resetAt) {
    entry.count = 0;
    entry.resetAt = now + RATE_LIMIT_WINDOW_MS;
  }

  entry.count++;
  rateLimitMap.set(key, entry);

  if (entry.count > RATE_LIMIT_MAX) {
    res.status(429).json({ error: "Too many requests. Try again later." });
    return false;
  }
  return true;
}

module.exports = {
  corsHeaders,
  requireApiKey,
  verifyPlaidWebhook,
  rateLimit,
};
