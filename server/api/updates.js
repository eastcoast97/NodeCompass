const { store } = require("./_lib/plaid");

module.exports = (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");

  const sinceCounter = parseInt(req.query.since || "0");
  res.json({
    hasUpdates: store.updateCounter > sinceCounter,
    counter: store.updateCounter,
    pendingTransactions: store.pendingTransactions.length,
    lastWebhookAt: store.lastWebhookAt,
    connectedBanks: store.accessTokens.length,
  });
};
