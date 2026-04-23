/**
 * Shared Plaid client and in-memory store for Vercel serverless functions.
 *
 * NOTE: Vercel serverless functions are stateless between cold starts.
 * In-memory storage works for the same warm instance but resets on cold starts.
 * For production, use a database (e.g., Vercel KV, Redis, or Supabase).
 * For personal use with Plaid sandbox, this is fine — the app re-syncs on connect.
 */

const { Configuration, PlaidApi, PlaidEnvironments, Products, CountryCode } = require("plaid");

// Trim all env vars — Vercel sometimes stores them with trailing newlines
const PLAID_CLIENT_ID = (process.env.PLAID_CLIENT_ID || "").trim();
const PLAID_SECRET = (process.env.PLAID_SECRET || "").trim();
const PLAID_ENV = (process.env.PLAID_ENV || "sandbox").trim();

const plaidConfig = new Configuration({
  basePath: PlaidEnvironments[PLAID_ENV],
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": PLAID_CLIENT_ID,
      "PLAID-SECRET": PLAID_SECRET,
      "Plaid-Version": "2020-09-14",
    },
  },
});

const plaidClient = new PlaidApi(plaidConfig);

// In-memory store (persists across warm invocations of the same instance)
const store = {
  accessTokens: [],       // { accessToken, itemId, institutionName }
  syncCursors: {},         // itemId -> cursor
  pendingTransactions: [], // Transactions waiting pickup
  pendingAccounts: [],     // Accounts cache
  lastWebhookAt: null,
  updateCounter: 0,
};

async function syncItemTransactions({ accessToken, itemId, institutionName }) {
  const cursor = store.syncCursors[itemId] || "";
  let added = [], modified = [], removed = [];
  let hasMore = true;
  let nextCursor = cursor;

  while (hasMore) {
    const response = await plaidClient.transactionsSync({
      access_token: accessToken,
      cursor: nextCursor,
      count: 500,
      options: { include_personal_finance_category: true },
    });

    added = added.concat(response.data.added);
    modified = modified.concat(response.data.modified);
    removed = removed.concat(response.data.removed);
    hasMore = response.data.has_more;
    nextCursor = response.data.next_cursor;
  }

  store.syncCursors[itemId] = nextCursor;

  if (added.length > 0) {
    const txns = added.map((t) => ({ ...t, institution_name: institutionName }));
    store.pendingTransactions = store.pendingTransactions.concat(txns);
    store.updateCounter++;
    store.lastWebhookAt = new Date().toISOString();
  }

  // Update accounts cache
  try {
    const accountsResp = await plaidClient.accountsGet({ access_token: accessToken });
    const accts = accountsResp.data.accounts.map((a) => ({
      ...a,
      institution_name: institutionName,
    }));
    store.pendingAccounts = store.pendingAccounts
      .filter((a) => a.institution_name !== institutionName)
      .concat(accts);
  } catch (e) {
    // Ignore accounts fetch error
  }
}

module.exports = { plaidClient, store, syncItemTransactions, Products, CountryCode, PLAID_ENV };
