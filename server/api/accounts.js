const { plaidClient, store } = require("./_lib/plaid");
const { corsHeaders, requireApiKey, rateLimit } = require("./_lib/auth");

module.exports = async (req, res) => {
  corsHeaders(res, "GET, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "GET") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;
  if (!requireApiKey(req, res)) return;

  try {
    if (store.accessTokens.length === 0) return res.json({ accounts: [] });

    if (store.pendingAccounts.length === 0) {
      for (const { accessToken, institutionName } of store.accessTokens) {
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
        store.pendingAccounts = store.pendingAccounts.concat(accounts);
      }
    }

    res.json({ accounts: store.pendingAccounts });
  } catch (error) {
    console.error("[Plaid] Accounts error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to fetch accounts" });
  }
};
