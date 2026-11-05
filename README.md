# NodeCompass

**A privacy-first life tracker that connects the dots across your money, health, and habits.**

Most tracking apps silo your data — one for spending, one for fitness, one for food. NodeCompass correlates all three on-device and surfaces the patterns between them: *"You spend ₹8,200/year on Tuesday 8am Starbucks runs"*, *"Your sleep drops 1.4h on days you eat out."*

Built with SwiftUI for iOS. Currently in TestFlight beta.

📄 [Privacy Policy](https://eastcoast97.github.io/NodeCompass/PRIVACY_POLICY.html)

---

## Why it's different

**Your data never leaves your phone.** No analytics SDK, no telemetry, no user accounts, no cloud sync of personal data. Transactions, health metrics, food logs, and location history live in the app's sandbox and Keychain. The only things that touch a network are:

- AI categorization — sends **merchant names only**, never amounts or account numbers
- Circles (opt-in social challenges) — shares challenge *progress*, never raw data
- Barcode lookups — sends the barcode digits, nothing else

This constraint shaped every architectural decision in the app.

---

## AI features

The most interesting engineering in this project is the **agentic coach** — natural language in, executed actions out.

### Agentic life coach

You type something like *"set me up for a lean bulk"* or *"cap my dining spend at 4,000/month"*. The model (Llama 3.3 via Groq) returns structured JSON that the app executes:

```json
{
  "type": "action",
  "action": "setDietPlan",
  "params": { "calories": 2400, "protein": 180, "carbs": 280, "fat": 80 },
  "response": "Based on your stats, 2,400 kcal with 180g protein..."
}
```

Supported actions: create budgets, savings goals, challenges, habits, diet plans; log meals, moods, and expenses.

Three design decisions worth noting:

- **Explicit scope boundaries.** The system prompt defines what the coach handles and what it doesn't. Ask it the capital of France and it returns `type: "outOfScope"` with a polite redirect rather than hallucinating an action.
- **Asks instead of guessing.** For diet plans it computes targets from body metrics (Mifflin-St Jeor BMR × activity factor ± goal delta). If height/weight/activity are missing, it returns a question rather than inventing numbers.
- **Actions are auditable.** Every executed action renders a badge in the chat, so the user always sees what the AI actually did.

### AI-generated diet plans with auto-tracking

A generated plan becomes a recurring daily challenge that tracks itself against your food log. Progress bars for calories and each macro, a streak counter that increments when you hit ≥80% on calories *and* protein, and a daily reset at midnight. No manual check-ins.

### LLM receipt parsing

Gmail receipts are messy — nested HTML tables, inconsistent formats, promotional noise. The pipeline:

1. Heuristic promo scoring filters obvious marketing
2. Borderline emails get an LLM classification pass
3. Real receipts go to an LLM extractor for merchant, amount, currency, and line items
4. Food-delivery emails get raw HTML (LLMs parse tables better than stripped text), plus a regex pass to recover the actual restaurant name — Uber Eats receipts say "Uber Eats", not "Sichuan Folk"
5. Regex fallback parser if the LLM returns nothing

### Other AI touches

- **Transaction categorization** — batched merchant-name classification, cached per merchant
- **Voice food logging** — on-device speech recognition parsed into structured food items with quantities and units
- **Barcode scanning** — VisionKit `DataScannerViewController` → OpenFoodFacts lookup → macro-scaled food entry

---

## Features

### 💰 Wealth
Bank sync via Plaid · Gmail receipt parsing · automatic categorization · budgets with per-category limits · savings goals with projections · subscription detection with cancellation deep-links · spending prediction

### ❤️ Health
Apple HealthKit (steps, sleep, workouts, heart rate, active calories) · food logging by voice, barcode, or manual entry · macro tracking · mood check-ins · habit tracking with auto-completion from location and health data

### 🧠 Mind
Life Score across four pillars · AI coach · solo and shared challenges · achievements and streaks · cross-pillar pattern insights

### 👥 Circles
Private groups of up to 8 friends. Shared challenges with live leaderboards, emoji reactions delivered as lock-screen push notifications. Sign in with Apple generates an anonymous UUID — no real names, no emails, no personal data on the server.

### 📍 Place intelligence
Battery-efficient visit detection correlates where you go with what you spend. All processing is on-device; raw GPS never leaves the phone.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  SwiftUI App (iOS 17+)                          │
│  ┌───────────┬───────────┬──────────┬────────┐  │
│  │  Today    │  Wealth   │  Health  │  Mind  │  │
│  └───────────┴───────────┴──────────┴────────┘  │
│                                                 │
│  Intelligence Layer (actor-isolated stores)     │
│  PatternEngine · LifeScoreEngine · NudgeEngine  │
│  ChallengeStore · FoodStore · PlaceIntelligence │
│                                                 │
│  Local persistence: JSON files + UserDefaults   │
│  Secrets: Keychain                              │
└─────────────────────────────────────────────────┘
         │                    │              │
    ┌────▼────┐      ┌────────▼──────┐  ┌────▼─────┐
    │  Groq   │      │    Vercel     │  │ Supabase │
    │ Llama   │      │  Plaid proxy  │  │ Circles  │
    │  3.3    │      │  APNs sender  │  │ + RLS    │
    └─────────┘      └───────────────┘  └──────────┘
```

**Serverless backend** (`server/`) — Node functions on Vercel. Proxies Plaid (keeps secrets off-device) and signs ES256 JWTs to deliver APNs pushes over HTTP/2, triggered by a Supabase database webhook on reaction inserts.

**Supabase** — Postgres with row-level security for Circles only. All mutations go through `SECURITY DEFINER` RPCs to avoid policy recursion. Realtime WebSocket for reactions, with a 15-second polling fallback since WebSocket delivery isn't guaranteed.

**Progressive disclosure** — `AppLearningStage` gates features behind data thresholds. A day-one user sees a simple dashboard; features unlock as the app accumulates enough data to make them useful.

---

## Tech stack

| Layer | Choice |
|---|---|
| UI | SwiftUI, iOS 17+ |
| Concurrency | Swift actors for all stores, `async/await` throughout |
| AI | Groq (Llama 3.3 70B) |
| Banking | Plaid |
| Email | Gmail API (read-only) |
| Health | HealthKit (read-only) |
| Backend | Vercel serverless (Node) |
| Social | Supabase (Postgres + Auth + Realtime) |
| Auth | Sign in with Apple |
| Push | APNs via HTTP/2 with ES256 JWT |
| Nutrition | OpenFoodFacts |
| Project gen | XcodeGen |

---

## Project structure

```
iosApp/iosApp/
├── Views/            SwiftUI screens (5 tabs + modals)
├── Intelligence/     Analysis engines and data stores
│   ├── Collectors/   HealthKit, location, transaction ingestion
│   ├── Analyzers/    Pattern detection
│   └── Models/       Domain models
├── Services/         External integrations
├── ViewModels/       Observable view models
└── Theme/            Design system (Aurora)

server/api/           Vercel serverless functions
shared/               Kotlin Multiplatform scaffolding (not yet linked)
```

~42,000 lines of Swift across 119 files.

---

## Building

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd iosApp
xcodegen generate
open iosApp.xcodeproj
```

The app runs without any API keys — every integration is optional and degrades gracefully. To enable the full feature set you'll need your own Groq key (free tier, entered in-app), Plaid credentials, a Google OAuth client, and a Supabase project.

---

## Engineering notes

A few problems that were more interesting than expected:

**Multi-account Gmail.** Google's iOS SDK only restores one account per cold launch, so a second connected inbox always appeared "signed out." Worked around it by persisting each account's refresh token in Keychain and exchanging it directly against Google's OAuth endpoint, bypassing the SDK's single-user restriction.

**Supabase RLS recursion.** A policy on `circles` queried `circle_members`, whose own policy queried `circle_members` again — infinite recursion. Fixed with a `SECURITY DEFINER` helper function that breaks the cycle.

**APNs key encoding.** Vercel flattens multi-line environment variables into single-line strings with spaces, which silently corrupts a PEM. Added a normalizer that detects the flattened form and reconstructs valid line breaks.

**Stale SwiftUI view state.** A challenge shared by a friend appeared inside the circle view but not on the dashboard. Root cause: `onAppear` doesn't re-fire when switching tabs in a `TabView`, so the local mirror never refreshed. Fixed with a notification-driven invalidation path.

---

## Status

In TestFlight beta. Roadmap: iCloud sync so history survives a device reset, Android via the Kotlin Multiplatform shared module, richer Circles features.

---

<sub>Built with [Claude Code](https://claude.com/claude-code) as a pair programmer.</sub>
