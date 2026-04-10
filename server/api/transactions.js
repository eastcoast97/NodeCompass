const { store, syncItemTransactions } = require("./_lib/plaid");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");

  if (req.method !== "GET") return res.status(405).json({ error: "Method not allowed" });

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
    res.status(500).json({ error: "Failed to fetch transactions" });
  }
};
