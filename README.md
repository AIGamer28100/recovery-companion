# Soter Recovery

A real-time voice companion for people navigating substance use urges, and for the
caregivers supporting them. Named for Soter, the Greek god of safety and deliverance
from harm. Zero-typing by design, for the moments when cognitive load is highest and
typing is the last thing someone can manage.

**Caregiver dashboard (live):** https://recovery-companion-hack.web.app
**Repo:** https://github.com/AIGamer28100/soter-recovery

**Sign in with any Google account — no allowlist, no test credentials to request.**
On first sign-in you pick a role, which determines everything you see next.

---

## Where things actually are right now

This project is mid-migration from a single web app to two front ends over one
Firebase backend — see `ARCHITECTURE.md` for the full picture and why. Stated
plainly, since the two don't fully match yet:

- **Target architecture:** a native Android app (Flutter, at the repo root — `lib/`,
  `android/`) for the person in recovery, and a web dashboard (`node-web/`) for their
  caregiver only.
- **Actual state today:** the Flutter app has auth, onboarding, and the live-audio
  pipeline (mic capture, native playback, barge-in) built and unit-tested, but not yet
  a finished crisis-call screen. The web app (`node-web/`) still contains the entire
  original patient experience (live voice, camera, tap-only fallback) alongside the
  caregiver dashboard — that code hasn't been removed yet, so **the deployed link
  above still works exactly like the original hackathon build** for both roles, while
  the Android app catches up.

If you want to see the caregiver-only target experience specifically, sign in and
pick "I'm a caregiver" — that path is fully caregiver-scoped already. Signing in as
"person in recovery" on the web today gets you the legacy full patient flow described
below, not the Android app.

---

## What it does

### Caregiver dashboard (`node-web/`, deployed, caregiver-scoped)

- **The person in recovery invites you** — they enter your Google email during their
  own onboarding. You then just sign in and pick "I'm a caregiver"; there is nothing
  to type and no way to attach yourself to someone who didn't nominate you.
- See their real activity stream, live, as it happens (Firestore `onSnapshot`).
- **Generate a script grounded in their actual recent patterns**, not a generic
  template. The prompt is built from a real summary of their logged events ("3
  craving spikes and a sensory overload in the last 40 minutes; most recent mood:
  overwhelmed"), so the advice responds to what's genuinely going on.

### Legacy patient flow (`node-web/`, still live, being retired)

Everything below still runs at the deployed link today, but is being superseded by
the Android app and is not the direction of future work:

- **Live voice** (`node-web/src/components/LiveApp.tsx`) — full-screen reactive orb,
  a real bidirectional audio WebSocket to Gemini Live, camera-frame grounding, live
  transcript of both sides.
- **Tap-only fallback** (`node-web/src/components/PatientScreen.tsx`) — three
  zero-typing scenario cards, mood check-in, box-breathing visualizer, one-tap
  emergency reset, and a proactive engine that opens an unprompted check-in when it
  detects rising stress (rapid tapping, long silences in higher-risk hours).
- **Evaluator Tools dock** (`node-web/src/components/EvaluatorDock.tsx`) — every
  control fires the identical production code path as its organic trigger (real
  Gemini calls, real Firestore writes, nothing canned).

### Patient app (Android, in progress)

`lib/` and `android/` at the repo root. Built so far: Google Sign-In, role/profile
onboarding (`lib/features/auth`, `lib/features/profile`), and the live-audio pipeline
— mic capture, a native Kotlin `AudioTrack` playback engine, echo cancellation,
barge-in (`lib/features/live_session`, `lib/platform/audio`). Not yet built: the
actual crisis-call screen UI (`DESIGN.md` §1.3) and camera/vision integration
(`DESIGN.md` §4). See `DESIGN.md` for the full design and `UX_AND_CLINICAL_GROUNDING.md`
for the clinically-grounded conversation design (Motivational Interviewing, Stages of
Change, harm reduction, trauma-informed care).

---

## GenAI services used, and exactly where

Both models run through **Firebase AI Logic**, called directly from the client —
web via `firebase/ai`, Android via the `firebase_ai` Dart SDK. There is no API key in
client code and no backend server; Firebase AI Logic proxies the call.

| Where | Model | What it powers |
|---|---|---|
| `node-web/src/lib/gemini.ts` | `gemini-flash-latest` | Legacy scenario interventions, proactive check-in, and both caregiver script generators (generic + pattern-personalized) — the caregiver script generator is the part still in active use |
| `node-web/src/lib/geminiLive.ts` | `gemini-2.5-flash-native-audio-preview-12-2025` | Legacy web live voice (being retired) |
| `lib/features/live_session/data/gemini_live_repository.dart` | `gemini-2.5-flash-native-audio-preview-12-2025` | The Android app's Live API session setup — currently uses a placeholder system instruction pending the `UX_AND_CLINICAL_GROUNDING.md` §B.8 rewrite being wired in |

Every response is generated live on each trigger. Nothing is precomputed, cached, or
substituted for a real call.

---

## How it works

- **Caregiver web app:** Vite + React + TypeScript + Tailwind CSS, in `node-web/`,
  deployed as a static SPA to Firebase Hosting via GitHub Actions on every push to
  `main`. No backend server.
- **Patient Android app:** Flutter, at the repo root, using Riverpod for state and
  `go_router` for navigation. Not yet published anywhere — build locally per below.
- **Auth:** Firebase Authentication, Google Sign-In only, shared by both apps. Role
  (patient/caregiver) is recorded on first sign-in and drives which experience loads.
- **Data:** Firebase Cloud Firestore, shared by both apps. Every write happens
  directly from the client on user action — no Cloud Functions.
- **GenAI:** [Firebase AI Logic](https://firebase.google.com/docs/ai-logic), calling
  the Gemini Developer API directly from the client. **No API key is present in
  either client's code or bundle.**

---

## Running it locally

### Caregiver web app

```bash
cd node-web
npm install
cp .env.example .env.local   # fill in your Firebase web config
npm run dev
```

The Firebase project needs Authentication (Google provider), Firestore, and Firebase
AI Logic enabled (`firebase init ailogic`). Live voice (legacy patient flow) needs
microphone permission and a modern browser (Chrome/Edge recommended) with WebSocket
and `getUserMedia`/camera support.

### Patient Android app

```bash
flutter pub get
flutter run          # or: flutter build apk --debug
```

Needs `google-services.json` (already committed — public client config, not a
secret) and an Android device or emulator with a working microphone for the live
audio pipeline.

---

## Security

### Credentials

Nothing secret is committed to this repository, and nothing secret reaches either
client.

- **No Gemini API key exists in either client.** Every model call goes through
  Firebase AI Logic, which brokers the request — so there is no AI key in the source,
  in `.env.example`, in either bundle, or in git history.
- **Firebase web/Android config is public by design.** `VITE_FIREBASE_*` values and
  `google-services.json`/`firebase_options.dart` ship in their respective clients
  because the SDKs need them to identify the project. They authorise nothing on their
  own: access is enforced by Firestore security rules and Auth authorized-domains.
  Web config is injected at build time from GitHub Actions secrets rather than being
  committed.
- **The deploy service account** lives only as the `FIREBASE_SERVICE_ACCOUNT` GitHub
  Actions secret. The key file was never written into the repo and was deleted
  locally after upload.
- `.gitignore` explicitly excludes `.env`, `.env.*` (except the example),
  service-account JSON, `.pem` and `.p12`. Only `.env.example` — which contains keys
  with no values — is tracked.

Verified by scanning full git history (`git log -S`) for the API key and for
private-key material, and by grepping the production web bundle: neither appears in
either.

### Rules and known gaps

- Firestore rules (`firestore.rules`) default-deny everything, scope each user to
  their own data, validate every field's type/enum/size, and make events, alerts,
  incidents and sessions append-only.
- **Linking is patient-initiated and consent-based.** A patient nominates a caregiver
  by email on their own profile; the caregiver is then recognised by their verified
  `auth.token.email`. A caregiver can never attach themselves to someone who didn't
  invite them, and revoking access is just removing the email.
- **Profile reads are scoped, not open.** `users/{uid}` is readable only by its owner
  or a nominated caregiver. Because rules are evaluated per document, a caregiver's
  `array-contains` query for their own email succeeds while an unconstrained listing
  of `/users` is denied — so the collection can't be enumerated and `emergencyContact`
  (a third party's name and phone) can't be harvested.

**Known gaps**, called out deliberately rather than papered over:

1. **Firebase App Check is not configured.** Firebase AI Logic recommends it to stop
   unauthorized clients burning your Gemini quota. It's the first thing to add before
   any real-world release.
2. **Relapse snapshots live in Firestore as base64, not Cloud Storage.** That keeps
   the Spark plan viable and the read path rule-scoped, but a production build should
   move them to Storage with signed URLs and a retention policy.
3. **The Android app's live-audio pipeline is unverified on a real device** — echo
   cancellation quality, barge-in latency, and foreground-service survival through
   screen lock are all flagged as needing real-device testing (`DESIGN.md` §3.6/§9),
   not yet done.

The rules are a solid first pass, not an exhaustively audited ruleset. They'd deserve
another dedicated review before this handled real patient data at scale.

---

## Assumptions and scope

- The caregiver's live view reflects one linked patient; there's no multi-patient or
  multi-caregiver management UI.
- Generated content is general wellness guidance — not a medical device, not a
  clinical assessment, and never mentions medication or dosages by design.
- Linking is one-directional and by email: the patient must have signed in at least
  once before a caregiver can link to them.
- Camera grounding only runs while a live voice session is open; there's no
  standalone camera mode.
