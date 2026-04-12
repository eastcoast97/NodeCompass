/**
 * NodeCompass Backend Server
 *
 * Event-driven architecture:
 *   - Plaid WEBHOOKS push new transactions to us (zero polling)
 *   - Gmail HISTORY API fetches only new emails since last check (1 API call)
 *   - App calls /api/updates to check for new data (lightweight)
 *
 * Security:
 *   - API key authentication for app endpoints (X-API-Key header)
 *   - Plaid webhook signature verification (Plaid-Verification header)
 *   - CORS restricted to configured origins
 *
 * Setup:
 *   1. Sign up at https://dashboard.plaid.com
 *   2. Copy .env.example to .env and add your keys
 *   3. npm install && npm start
 */

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const crypto = require("crypto");
const {
  Configuration,
  PlaidApi,
  PlaidEnvironments,
  Products,
  CountryCode,
} = require("plaid");

const app = express();

// --- CORS: restrict origins in production ---
const corsOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(",")
  : "*";
app.use(cors({ origin: corsOrigins }));

// --- Webhook endpoint needs raw body for signature verification ---
app.use("/api/plaid_webhook", express.raw({ type: "application/json" }));
app.use(express.json());

// --- API Key Authentication Middleware ---
const API_KEY = process.env.API_KEY;

function requireApiKey(req, res, next) {
  // Skip auth if no API_KEY is configured (dev mode)
  if (!API_KEY) return next();

  const provided = req.headers["x-api-key"];
  if (!provided || provided !== API_KEY) {
    return res.status(401).json({ error: "Unauthorized: invalid or missing API key" });
  }
  next();
}

// --- Rate Limiting (simple in-memory) ---
const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 60; // 60 requests per minute

function rateLimit(req, res, next) {
  const key = req.ip;
  const now = Date.now();
  const entry = rateLimitMap.get(key) || { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };

  if (now > entry.resetAt) {
    entry.count = 0;
    entry.resetAt = now + RATE_LIMIT_WINDOW_MS;
  }

  entry.count++;
  rateLimitMap.set(key, entry);

  if (entry.count > RATE_LIMIT_MAX) {
    return res.status(429).json({ error: "Too many requests. Try again later." });
  }
  next();
}

app.use("/api", rateLimit);

// --- Plaid Client Setup ---
const plaidConfig = new Configuration({
  basePath: PlaidEnvironments[process.env.PLAID_ENV || "sandbox"],
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
      "PLAID-SECRET": process.env.PLAID_SECRET,
      "Plaid-Version": "2020-09-14",
    },
  },
});
const plaidClient = new PlaidApi(plaidConfig);

// --- In-memory storage (replace with DB for production) ---
let accessTokens = []; // { accessToken, itemId, institutionName }
let syncCursors = {}; // itemId -> cursor
let pendingTransactions = []; // Transactions waiting to be picked up by the app
let pendingAccounts = []; // Accounts cache
let lastWebhookAt = null; // Track when Plaid last notified us
let updateCounter = 0; // Increments when new data arrives (app polls this)

// --- Health Check (no auth required) ---
app.get("/health", (req, res) => {
  res.json({ status: "ok", env: process.env.PLAID_ENV || "sandbox" });
});

// ═══════════════════════════════════════════════════
// PLAID ENDPOINTS
// ═══════════════════════════════════════════════════

// --- Create Link Token (with webhook URL) ---
app.post("/api/create_link_token", requireApiKey, async (req, res) => {
  try {
    const webhookUrl = process.env.WEBHOOK_URL || undefined;

    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: "nodecompass-user-1" },
      client_name: "NodeCompass",
      products: [Products.Transactions],
      country_codes: [CountryCode.Us],
      language: "en",
      // Plaid will POST to this URL when new transactions are available
      webhook: webhookUrl,
      // Required for OAuth bank flows
      redirect_uri: "https://cdn.plaid.com/link/redirect/nodecompass",
    });

    console.log("[Plaid] Link token created" + (webhookUrl ? ` (webhook: ${webhookUrl})` : " (no webhook)"));
    res.json({ link_token: response.data.link_token });
  } catch (error) {
    console.error("[Plaid] Link token error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to create link token" });
  }
});

// --- Exchange Public Token ---
app.post("/api/exchange_token", requireApiKey, async (req, res) => {
  try {
    const { public_token, institution_name } = req.body;

    const response = await plaidClient.itemPublicTokenExchange({
      public_token,
    });

    const accessToken = response.data.access_token;
    const itemId = response.data.item_id;

    accessTokens.push({ accessToken, itemId, institutionName: institution_name || "Bank" });

    console.log(`[Plaid] Bank connected: ${institution_name} (item: ${itemId})`);

    // Do initial transaction sync immediately
    await syncPlaidTransactions(itemId);

    res.json({ status: "ok", item_id: itemId });
  } catch (error) {
    console.error("[Plaid] Token exchange error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to exchange token" });
  }
});

// --- Plaid Webhook Receiver ---
// Plaid calls this automatically when new transactions are available.
// Verifies webhook signature when PLAID_WEBHOOK_SECRET is configured.
app.post("/api/plaid_webhook", async (req, res) => {
  // Verify webhook signature if configured
  const webhookSecret = process.env.PLAID_WEBHOOK_SECRET;
  if (webhookSecret) {
    const signature = req.headers["plaid-verification"];
    if (!signature) {
      console.warn("[Plaid Webhook] Missing signature header — rejecting");
      return res.status(401).json({ error: "Missing webhook signature" });
    }

    try {
      const body = typeof req.body === "string" ? req.body : req.body.toString("utf-8");
      const expectedSignature = crypto
        .createHmac("sha256", webhookSecret)
        .update(body)
        .digest("hex");

      if (signature !== expectedSignature) {
        console.warn("[Plaid Webhook] Invalid signature — rejecting");
        return res.status(401).json({ error: "Invalid webhook signature" });
      }
    } catch (e) {
      console.error("[Plaid Webhook] Signature verification error:", e.message);
      return res.status(500).json({ error: "Signature verification failed" });
    }
  }

  // Parse body (may be raw Buffer from express.raw)
  let payload;
  try {
    payload = typeof req.body === "string"
      ? JSON.parse(req.body)
      : Buffer.isBuffer(req.body)
        ? JSON.parse(req.body.toString("utf-8"))
        : req.body;
  } catch (e) {
    console.error("[Plaid Webhook] Failed to parse body:", e.message);
    return res.status(400).json({ error: "Invalid JSON" });
  }

  const { webhook_type, webhook_code, item_id } = payload;

  console.log(`[Plaid Webhook] ${webhook_type}.${webhook_code} for item ${item_id}`);

  if (webhook_type === "TRANSACTIONS") {
    switch (webhook_code) {
      case "SYNC_UPDATES_AVAILABLE":
        // New transactions! Fetch them.
        await syncPlaidTransactions(item_id);
        break;
      case "INITIAL_UPDATE":
      case "HISTORICAL_UPDATE":
        // Initial/historical data ready after first link
        await syncPlaidTransactions(item_id);
        break;
      default:
        console.log(`[Plaid Webhook] Unhandled code: ${webhook_code}`);
    }
  }

  // Always respond 200 to acknowledge the webhook
  res.json({ status: "ok" });
});

// --- Internal: Sync transactions for a specific item ---
async function syncPlaidTransactions(itemId) {
  const item = accessTokens.find((t) => t.itemId === itemId);
  if (!item) {
    // Try all items if specific one not found (for initial sync)
    for (const t of accessTokens) {
      await syncItemTransactions(t);
    }
    return;
  }
  await syncItemTransactions(item);
}

async function syncItemTransactions({ accessToken, itemId, institutionName }) {
  try {
    const cursor = syncCursors[itemId] || "";
    let added = [], modified = [], removed = [];
    let hasMore = true;
    let nextCursor = cursor;

    while (hasMore) {
      const response = await plaidClient.transactionsSync({
        access_token: accessToken,
        cursor: nextCursor,
        count: 500,
        options: { include_personal_finance_category: true },
      });

      added = added.concat(response.data.added);
      modified = modified.concat(response.data.modified);
      removed = removed.concat(response.data.removed);
      hasMore = response.data.has_more;
      nextCursor = response.data.next_cursor;
    }

    syncCursors[itemId] = nextCursor;

    if (added.length > 0) {
      const txns = added.map((t) => ({ ...t, institution_name: institutionName }));
      pendingTransactions = pendingTransactions.concat(txns);
      updateCounter++;
      lastWebhookAt = new Date().toISOString();
      console.log(`[Plaid] ${added.length} new transactions from ${institutionName}`);
    }

    // Update accounts cache
    try {
      const accountsResp = await plaidClient.accountsGet({ access_token: accessToken });
      const accts = accountsResp.data.accounts.map((a) => ({
        ...a,
        institution_name: institutionName,
      }));
      // Replace accounts for this institution
      pendingAccounts = pendingAccounts
        .filter((a) => a.institution_name !== institutionName)
        .concat(accts);
    } catch (e) {
      console.error("[Plaid] Accounts fetch error:", e.message);
    }
  } catch (error) {
    console.error(`[Plaid] Sync error for ${itemId}:`, error.response?.data || error.message);
  }
}

// --- Get Transactions (app picks up pending transactions) ---
app.get("/api/transactions", requireApiKey, async (req, res) => {
  try {
    // If no pending transactions but we have access tokens, do a fresh sync
    if (pendingTransactions.length === 0 && accessTokens.length > 0) {
      for (const item of accessTokens) {
        await syncItemTransactions(item);
      }
    }

    const txns = [...pendingTransactions];
    pendingTransactions = []; // Clear after pickup

    res.json({ transactions: txns, accounts: pendingAccounts });
  } catch (error) {
    console.error("[Plaid] Transaction fetch error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to fetch transactions" });
  }
});

// --- Get Connected Accounts ---
app.get("/api/accounts", requireApiKey, async (req, res) => {
  try {
    if (accessTokens.length === 0) return res.json({ accounts: [] });

    if (pendingAccounts.length === 0) {
      // Fetch fresh if cache is empty
      for (const { accessToken, institutionName } of accessTokens) {
        const response = await plaidClient.accountsGet({ access_token: accessToken });
        const accounts = response.data.accounts.map((a) => ({
          account_id: a.account_id,
          name: a.name,
          official_name: a.official_name,
          type: a.type,
          subtype: a.subtype,
          mask: a.mask,
          institution_name: institutionName,
        }));
        pendingAccounts = pendingAccounts.concat(accounts);
      }
    }

    res.json({ accounts: pendingAccounts });
  } catch (error) {
    console.error("[Plaid] Accounts error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to fetch accounts" });
  }
});

// ═══════════════════════════════════════════════════
// LIGHTWEIGHT UPDATE CHECK
// The app calls this frequently — it's nearly free.
// Returns whether new data is available without fetching anything.
// ═══════════════════════════════════════════════════

app.get("/api/updates", requireApiKey, (req, res) => {
  const sinceCounter = parseInt(req.query.since || "0");
  res.json({
    hasUpdates: updateCounter > sinceCounter,
    counter: updateCounter,
    pendingTransactions: pendingTransactions.length,
    lastWebhookAt,
    connectedBanks: accessTokens.length,
  });
});

// --- Start Server ---
const PORT = process.env.PORT || 8080;
// Bind to 0.0.0.0 so the phone can reach it over WiFi
app.listen(PORT, "0.0.0.0", () => {
  console.log(`\n NodeCompass server running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.PLAID_ENV || "sandbox"}`);
  console.log(`   Plaid Client ID: ${process.env.PLAID_CLIENT_ID ? "configured" : "missing"}`);
  console.log(`   Plaid Secret: ${process.env.PLAID_SECRET ? "configured" : "missing"}`);
  console.log(`   API Key Auth: ${API_KEY ? "enabled" : "disabled (set API_KEY in .env)"}`);
  console.log(`   Rate Limiting: ${RATE_LIMIT_MAX} req/min`);
  console.log(`   Webhook URL: ${process.env.WEBHOOK_URL || "not set (set WEBHOOK_URL in .env for production)"}`);
  console.log(`   Webhook Sig: ${process.env.PLAID_WEBHOOK_SECRET ? "enabled" : "disabled (set PLAID_WEBHOOK_SECRET)"}`);
  console.log(`\n   Endpoints:`);
  console.log(`   POST /api/create_link_token  - Get Plaid Link token`);
  console.log(`   POST /api/exchange_token     - Exchange public token`);
  console.log(`   POST /api/plaid_webhook      - Plaid webhook receiver`);
  console.log(`   GET  /api/transactions       - Fetch new transactions`);
  console.log(`   GET  /api/accounts           - Get connected accounts`);
  console.log(`   GET  /api/updates?since=N    - Check for new data (lightweight)\n`);
});
