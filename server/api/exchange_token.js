const { plaidClient, store, syncItemTransactions } = require("./_lib/plaid");
const { corsHeaders, requireApiKey, rateLimit } = require("./_lib/auth");

module.exports = async (req, res) => {
  corsHeaders(res, "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;
  if (!requireApiKey(req, res)) return;

  try {
    const { public_token, institution_name } = req.body;

    const response = await plaidClient.itemPublicTokenExchange({ public_token });
    const accessToken = response.data.access_token;
    const itemId = response.data.item_id;

    store.accessTokens.push({ accessToken, itemId, institutionName: institution_name || "Bank" });

    // Initial sync
    await syncItemTransactions({ accessToken, itemId, institutionName: institution_name || "Bank" });

    res.json({ status: "ok", item_id: itemId });
  } catch (error) {
    console.error("[Plaid] Token exchange error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to exchange token" });
  }
};
