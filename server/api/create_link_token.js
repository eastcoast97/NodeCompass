const { plaidClient, Products, CountryCode } = require("./_lib/plaid");
const { corsHeaders, requireApiKey, rateLimit } = require("./_lib/auth");

module.exports = async (req, res) => {
  corsHeaders(res, "POST, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

  if (!rateLimit(req, res)) return;
  if (!requireApiKey(req, res)) return;

  try {
    const webhookUrl = process.env.WEBHOOK_URL || undefined;

    const response = await plaidClient.linkTokenCreate({
      user: { client_user_id: "nodecompass-user-1" },
      client_name: "NodeCompass",
      products: [Products.Transactions],
      country_codes: [CountryCode.Us],
      language: "en",
      webhook: webhookUrl,
    });

    res.json({ link_token: response.data.link_token });
  } catch (error) {
    console.error("[Plaid] Link token error:", error.response?.data || error.message);
    res.status(500).json({ error: "Failed to create link token" });
  }
};
