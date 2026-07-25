# Recovery Companion

A multi-modal, GenAI-powered recovery and prevention platform for individuals
navigating substance use disorders and their caregivers. Zero-typing by design: large
tap targets, no forms, no journaling — built for moments when cognitive load is highest.

**Live app:** https://recovery-companion-hack.web.app
**Repo:** https://github.com/AIGamer28100/recovery-companion

## What it does

Sign in with Google, land on a single high-contrast screen, and tap a state:

- **Urge / Panic / "show me a coping technique"** — each is a distinct system
  instruction sent live to Gemini, which returns a personalized script (grounding
  technique, next concrete action). Nothing here is hardcoded — every response is a
  real API call, rendered on screen and spoken aloud.
- **Mood check-in** (tap-only, 5 options) — feeds as context into the next AI call and
  logs a real-time check-in.
- **Proactive engine** — a client-side hook watches for signs of elevated stress
  (rapid/chaotic tapping, long idle periods during high-risk hours) and can surface an
  intervention on its own, without the user asking.
- **Caregiver view** — a live, Firestore-backed stream of alerts and scripts generated
  in response to the user's activity.
- **Evaluator dock** — a discreet control panel that lets you trigger every core flow
  on demand (camera-blocked fallback, a crisis event, a caregiver sync) without waiting
  for real conditions to occur. Every button calls the exact same code path as the
  organic trigger — nothing here is a separate mocked demo.

## How it works

- **Frontend:** Vite + React + TypeScript + Tailwind CSS, deployed as a static SPA to
  Firebase Hosting via GitHub Actions on every push to `main`. No backend server.
- **Auth:** Firebase Authentication, Google Sign-In only — sign in with any Google
  account, no special test credentials needed.
- **Data:** Firebase Cloud Firestore. All writes (check-ins, alerts, events) happen
  directly from the client on user action — no Cloud Functions, secured by Firestore
  rules that scope every user to their own data and validate every field (see
  `firestore.rules`). These are a solid first-pass prototype, not an exhaustively
  audited ruleset — worth another pass before this handles real user data at scale.
- **GenAI:** [Firebase AI Logic](https://firebase.google.com/docs/ai-logic) (`firebase/ai`),
  which calls the Gemini Developer API directly from the browser through Firebase — no
  API key is ever present in client code or bundled into the app.

## GenAI services used, and where

- **Gemini 2.5 Flash, via Firebase AI Logic** — `src/lib/gemini.ts`. Powers every
  personalized intervention script (the 3 tap-matrix scenarios), the caregiver script
  generator, and the proactive engine's automated alerts. Called live on every trigger;
  nothing is precomputed or cached as a substitute for a real response.

## Assumptions

- The caregiver view reflects the same signed-in user's own alert stream — there's no
  second user/session simulated for it.
- Generated content is general wellness guidance, not a medical device or clinical
  assessment.
- Any Google account can sign in and exercise every feature; there's no separate
  allowlist to configure for evaluation.
- Firebase App Check (recommended by Firebase AI Logic to prevent quota abuse from
  unauthorized clients) is not configured given the build window — a known gap, not an
  oversight, and the first thing to add before any wider release.
