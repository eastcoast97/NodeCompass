const { corsHeaders } = require("./_lib/auth");

module.exports = (req, res) => {
  corsHeaders(res, "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).end();
  res.json({ status: "ok", env: (process.env.PLAID_ENV || "sandbox").trim() });
};
