const { store, syncItemTransactions } = require("./_lib/plaid");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");

  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  const { webhook_type, webhook_code, item_id } = req.body;

  if (webhook_type === "TRANSACTIONS") {
    const item = store.accessTokens.find((t) => t.itemId === item_id);
    if (item) {
      await syncItemTransactions(item);
    }
  }

  res.json({ status: "ok" });
};
