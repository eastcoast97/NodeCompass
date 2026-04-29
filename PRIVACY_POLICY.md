# NodeCompass Privacy Policy

**Last updated: April 29, 2026**

NodeCompass is a privacy-first life tracking app. It helps you connect the dots across your money, health, and habits — without sending your personal data to a server we control.

This policy explains what data NodeCompass touches, where it lives, and what (if anything) leaves your device.

---

## TL;DR — the short version

- **Your data lives on your phone.** Transactions, health stats, food logs, mood entries, photos of receipts — none of it is sent to NodeCompass servers.
- **The only things that leave your device** are: (1) AI categorization requests (merchant names only, never amounts or accounts) when you connect a Groq API key, (2) social interactions inside Circles you create or join (challenge progress, reactions), (3) push notifications routed through Apple, and (4) one-shot lookups to OpenFoodFacts when you scan a barcode.
- **Every integration is optional.** You decide what to connect. Skipping any one doesn't break the rest of the app.

---

## What data NodeCompass handles

### 1. On-device only — never leaves your phone

These data types are stored locally on your device using iOS Keychain and the app's sandboxed storage. They are never transmitted to NodeCompass servers and we have no way to access them.

- **Transactions**: amount, merchant, category, account, date — synced from your bank via Plaid (when connected) or parsed from email receipts (when Gmail is connected). Stored locally.
- **Health data**: steps, workouts, sleep, heart rate, active calories — read from Apple HealthKit when you grant access. Used to compute insights and life score on-device. Never written back.
- **Food log**: meal entries, calories, macros, photos. Logged manually, by voice, or by scanning barcodes.
- **Mood entries**: daily mood selections and optional notes.
- **Habits and challenges**: which habits you track, your streaks, completed challenges.
- **Goals and budgets**: your saving targets, spending limits, deadlines.
- **Location data**: visit detection runs entirely on-device (when you opt in to passive location). Used to associate spending with places you visit. Raw GPS data never leaves your phone.

### 2. Connected services — what they see

NodeCompass uses standard third-party services for specific tasks. Each runs on its own privacy terms — we don't see or store the data passing through them.

| Service | What it does | What it sees | Privacy link |
|---|---|---|---|
| **Plaid** | Bank account connection | Bank credentials and transactions you authorize | https://plaid.com/legal/#consumers |
| **Google (Gmail)** | Read receipt emails (read-only) | Receipt-shaped emails in your Gmail inbox | https://policies.google.com/privacy |
| **Apple HealthKit** | Health data on iOS | Whatever health metrics you grant | Apple — on-device |
| **Groq** | AI categorization and AI Coach (optional, requires your free API key) | Merchant names and conversation prompts you send to the coach | https://groq.com/privacy-policy |
| **OpenFoodFacts** | Barcode → nutrition lookup | The barcode digits only (no product photos, no user info) | https://world.openfoodfacts.org/terms-of-use |
| **Apple Push Notifications (APNs)** | Routes notifications to your phone | An anonymous device token | Apple — on-device |

### 3. Multiplayer — Circles

NodeCompass has an optional "Circles" feature that lets you compete on shared challenges with friends. To enable it, the app uses Supabase (a backend service) to coordinate between members.

**What's stored on the Supabase backend when you use Circles:**
- An anonymous user ID (a UUID generated on first Sign in with Apple — not your Apple ID, not your email)
- A display name and emoji avatar you chose for yourself (e.g., "Ram", 👨)
- Circle memberships (which circles you're in, which you created)
- Shared challenge definitions and members' progress percentages on those challenges
- Reactions you send and receive (emoji + timestamp)
- Your APNs device token, used only to deliver push notifications when a friend reacts to you

**What is NOT stored on Supabase:**
- Your real name, email, or Apple ID
- Bank account numbers, balances, or transactions
- Health data, food log, mood entries
- Anything outside an explicit shared challenge you opted into

If you don't use Circles, none of this data exists for your account. Sign in with Apple is requested only when you create or join your first Circle.

### 4. Things NodeCompass does NOT collect

- We don't run analytics or telemetry. There is no Firebase, Mixpanel, Segment, Amplitude, or any other tracking SDK in the app.
- We don't have user accounts (other than the optional anonymous ID for Circles described above).
- We don't sell, share, or monetize your data. The app has no ads.
- We don't track you across other apps or websites.

---

## How permissions are used

When the app asks iOS for permission to access something, here's what each permission is used for:

- **Microphone**: voice-based food logging. Audio is processed on-device using iOS Speech Recognition and never uploaded.
- **Speech recognition**: same — on-device transcription for voice food logging.
- **Camera**: barcode scanning for packaged food. Only barcode digits are sent (to OpenFoodFacts); no images leave your phone.
- **Health data (HealthKit)**: read-only access to steps, workouts, sleep, heart rate, calories. Never written or modified.
- **Face ID**: optional, used only to lock the app behind biometric authentication.
- **Location (when in use)**: optional, used to associate spending with places you visit. Processing is on-device.
- **Location (always)**: optional, lets the app passively learn your routines when not open. Same on-device processing.
- **Push notifications**: optional, used to deliver reaction-based alerts from Circles, plus locally-scheduled reminders (food logging, habit nudges) that originate on-device.

You can revoke any of these permissions at any time in iOS Settings → NodeCompass.

---

## Data export and deletion

- **Export your data**: in NodeCompass, open the Today tab → tap the people icon (top right) → Export Data. Produces a JSON archive of everything stored locally.
- **Delete data**: You tab → Data & App → Clear All Data. This wipes all local storage. Connected integrations (Plaid, Gmail) can be disconnected from the You tab Integrations section.
- **Delete a Circle account**: leaving every circle you're a member of removes your records from those circles. To remove your anonymous Supabase identity entirely, contact us at the email below.

---

## Children's privacy

NodeCompass is not directed at children under 13. We do not knowingly collect data from children under 13. If you believe a child has used NodeCompass, please contact us so we can remove the data.

---

## Changes to this policy

If we change this policy materially, we will update the "Last updated" date at the top and surface a notice in the app on next launch.

---

## Contact

Questions, requests, complaints, or data deletion requests:

**achuthanram97@gmail.com**

---

*NodeCompass is built with the principle that your life data is yours alone. Everything in this document reflects that.*
