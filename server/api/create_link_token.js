const { plaidClient, Products, CountryCode } = require("./_lib/plaid");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "Method not allowed" });

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
    res.status(500).json({ error: "Failed to create link token" });
  }
};
