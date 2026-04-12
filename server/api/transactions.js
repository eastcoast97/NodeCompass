const { store, syncItemTransactions } = require("./_lib/plaid");
const { corsHeaders, requireApiKey, rateLimit } = require("./_lib/auth");

module.exports = async (req, res) => {
  corsHeaders(res, "GET, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "GET") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;
  if (!requireApiKey(req, res)) return;

  try {
    // If no pending but have tokens, do fresh sync
    if (store.pendingTransactions.length === 0 && store.accessTokens.length > 0) {
      for (const item of store.accessTokens) {
        await syncItemTransactions(item);
      }
    }

    const txns = [...store.pendingTransactions];
    store.pendingTransactions = [];

    res.json({ transactions: txns, accounts: store.pendingAccounts });
  } catch (error) {
    console.error("[Plaid] Transaction fetch error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to fetch transactions" });
  }
};
