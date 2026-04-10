const { plaidClient, store, syncItemTransactions } = require("./_lib/plaid");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

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
    res.status(500).json({ error: "Failed to exchange token" });
  }
};
