const { store, syncItemTransactions } = require("./_lib/plaid");
const { corsHeaders, verifyPlaidWebhook, rateLimit } = require("./_lib/auth");

module.exports = async (req, res) => {
  corsHeaders(res, "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;

  // Verify Plaid webhook signature if PLAID_WEBHOOK_SECRET is configured
  if (!verifyPlaidWebhook(req, res)) return;

  const { webhook_type, webhook_code, item_id } = req.body;
  console.log(`[Plaid Webhook] ${webhook_type}.${webhook_code} for item ${item_id}`);

  if (webhook_type === "TRANSACTIONS") {
    const item = store.accessTokens.find((t) => t.itemId === item_id);
    if (item) {
      await syncItemTransactions(item);
    }
  }

  res.json({ status: "ok" });
};
