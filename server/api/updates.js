const { store } = require("./_lib/plaid");
const { corsHeaders, requireApiKey, rateLimit } = require("./_lib/auth");

module.exports = (req, res) => {
  corsHeaders(res, "GET, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "GET") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;
  if (!requireApiKey(req, res)) return;

  const sinceCounter = parseInt(req.query.since || "0");
  res.json({
    hasUpdates: store.updateCounter > sinceCounter,
    counter: store.updateCounter,
    pendingTransactions: store.pendingTransactions.length,
    lastWebhookAt: store.lastWebhookAt,
    connectedBanks: store.accessTokens.length,
  });
};
