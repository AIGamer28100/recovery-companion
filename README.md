# Soter Recovery

A real-time voice companion for people navigating substance use urges, and for the
caregivers supporting them — modeled on the Google Gemini Live app: a live spoken
conversation is the primary interface, not one feature buried among others. Zero-typing
by design, for the moments when cognitive load is highest and typing is the last thing
someone can manage.

**Live app:** https://recovery-companion-hack.web.app
**Repo:** https://github.com/AIGamer28100/soter-recovery

**Sign in with any Google account — no allowlist, no test credentials to request.**
On first sign-in you pick a role, which determines everything you see next.

---

## How to test it in 2 minutes

1. Open the live app and **sign in with any Google account**.
2. Pick **"person in recovery"** on first sign-in.
3. You land on the full-screen voice orb. Tap **"Start talking"**, allow the mic, and
   talk — the model listens and answers out loud, and you can interrupt it mid-sentence.
4. Tap the camera icon. Show it a real object nearby and ask what it sees — it will
   describe or reference only what's actually in frame.
5. Watch the **live transcript** panel fill in as you talk, for both sides of the
   conversation.
6. Tap **"No mic? Use tap-only support instead"** to see the fallback screen: three
   scenario cards, box-breathing visualizer, mood check-in, emergency reset.
7. Scroll to the bottom of that fallback screen and open **Evaluator Tools** — every
   control there fires the identical production code path as its organic trigger (real
   Gemini calls, real Firestore writes, nothing canned).

---

## What it does

### If you're the person in recovery — Live voice (primary)

- **`src/components/LiveApp.tsx`** is the screen you land on: full-screen, dark, a
  centered reactive orb, a bottom control bar. Tap "Start talking" to open a real
  bidirectional audio WebSocket to Gemini Live — you talk, the model responds out loud,
  and you can interrupt it mid-response.
- **Camera toggle** — turning the camera on streams JPEG frames at 1 FPS
  (`src/lib/videoStream.ts`, via `session.sendVideoRealtime`) so Gemini can actually see
  the room and ground you using real objects it sees ("that mug on your left — pick it
  up, tell me how cold it feels"). The system instruction in `src/lib/geminiLive.ts`
  explicitly forbids inventing objects it can't see; if the camera is off, it grounds you
  through breath and body instead.
- **Live transcript of both sides** — `src/lib/liveTee.ts` solves a real constraint:
  `LiveSession.receive()` supports exactly one consumer, and `startAudioConversation`
  claims it internally to drive audio playback. A second loop reading transcripts would
  silently steal chunks from that consumer and make playback choppy. The tee wraps the
  session in a `Proxy`, consumes the real stream exactly once, forwards every message
  untouched to audio playback, and mirrors a copy out to render the transcript. It's a
  small file but the actual engineering problem in this feature.
- **One-tap emergency reset** and a **proactive engine** watching for rising stress
  (rapid, chaotic tapping; long silences during historically higher-risk hours) are still
  present in the tap-only screen below.

### Fallback — tap-only support

**`src/components/PatientScreen.tsx`** is reachable via "No mic? Use tap-only support
instead" on the voice screen, for devices without a mic or moments someone can't speak
out loud. Fully working, real Gemini calls throughout:

- **Three zero-typing scenario cards** — Physical Tension, Sensory Overload, Craving
  Spike. Each sends a distinct system instruction to Gemini with current context (mood,
  time of day) and gets back a personalized script: what's happening, one concrete
  grounding technique for the next 30 seconds, one small next step. Rendered on screen and
  read aloud.
- **Tap-only mood check-in**, feeding as real context into the next AI call.
- **Box-breathing visualizer** — pure CSS, no network, works if everything else fails.
- **One-tap emergency reset** — silences voice and clears the screen back to calm.
- **Proactive engine** — a client-side hook watching for rising stress. When it fires, it
  generates an unprompted check-in rather than waiting to be asked.
- **Evaluator Tools dock** at the bottom of this screen — see below.

### If you're a caregiver

- **The person in recovery invites you** — they enter your Google email during their own
  onboarding. You then just sign in and pick "I'm a caregiver"; there is nothing to type
  and no way to attach yourself to someone who didn't nominate you.
- See their real activity stream, live, as it happens (Firestore `onSnapshot`).
- **Generate a script grounded in their actual recent patterns**, not a generic template.
  The prompt is built from a real summary of their logged events ("3 craving spikes and a
  sensory overload in the last 40 minutes; most recent mood: overwhelmed"), so the advice
  responds to what's genuinely going on.

### For evaluators

A discreet **Evaluator Tools** dock sits at the bottom of the tap-only fallback screen
(`src/components/EvaluatorDock.tsx`) so you can exercise every flow immediately instead of
waiting for real conditions.

| Control | What it does |
|---|---|
| Simulate crisis event | Fires the proactive engine's elevated-stress intervention |
| Test caregiver sync | Generates a caregiver script and writes it to their live feed |
| Simulate voice unavailable | Forces the tap-only fallback, as on a device with no mic |

**Every one of these calls the exact same function as its organic trigger** — real Gemini
API calls, real Firestore writes. There is no separate simulated or mocked path anywhere
in this dock; a canned "demo mode" would defeat the point of having it. This matters
because judges run a hands-on functional test, and anything static or faked is an
instant disqualification — this dock is built specifically so you can verify that isn't
happening.

---

## GenAI services used, and exactly where

Both models run through **Firebase AI Logic** (`firebase/ai`), called directly from the
browser. There is no API key in client code and no backend server — Firebase AI Logic
proxies the call.

| Where | Model | What it powers |
|---|---|---|
| `src/lib/gemini.ts` | `gemini-flash-latest` | The three scenario interventions, the proactive elevated-stress check-in, and both caregiver script generators (generic + pattern-personalized) |
| `src/lib/geminiLive.ts` | `gemini-2.5-flash-native-audio-preview-12-2025` | The Live API: real-time bidirectional voice (native audio in and out) over WebSocket, plus camera-frame grounding |

Every response is generated live on each trigger. Nothing is precomputed, cached, or
substituted for a real call — and when a call fails, the UI says so plainly rather than
falling back to a canned script that would be indistinguishable from a hardcoded one.

---

## How it works

- **Frontend:** Vite + React + TypeScript + Tailwind CSS, deployed as a static SPA to
  Firebase Hosting via GitHub Actions on every push to `main`. No backend server.
- **Auth:** Firebase Authentication, Google Sign-In only. Role (patient/caregiver) is
  recorded on first sign-in and drives which experience loads.
- **Data:** Firebase Cloud Firestore. Every write (check-ins, interventions, alerts,
  voice sessions) happens directly from the client on user action — no Cloud Functions.
- **GenAI:** [Firebase AI Logic](https://firebase.google.com/docs/ai-logic) (`firebase/ai`),
  calling the Gemini Developer API directly from the browser through Firebase. **No API
  key is present in client code or bundled into the app.**

---

## Running it locally

```bash
npm install
cp .env.example .env.local   # fill in your Firebase web config
npm run dev
```

The Firebase project needs Authentication (Google provider), Firestore, and Firebase AI
Logic enabled (`firebase init ailogic`). Live voice needs microphone permission and a
modern browser (Chrome/Edge recommended) with WebSocket and `getUserMedia`/camera
support.

---

## Security

### Credentials

Nothing secret is committed to this repository, and nothing secret reaches the browser.

- **No Gemini API key exists in the client at all.** Every model call goes through
  Firebase AI Logic, which brokers the request — so there is no AI key in the source,
  in `.env.example`, in the bundle, or in git history.
- **Firebase web config is public by design.** `VITE_FIREBASE_*` values ship in the
  client bundle because the SDK needs them to identify the project. They authorise
  nothing on their own: access is enforced by Firestore security rules and Auth
  authorized-domains. They're injected at build time from GitHub Actions secrets rather
  than being committed.
- **The deploy service account** lives only as the `FIREBASE_SERVICE_ACCOUNT` GitHub
  Actions secret. The key file was never written into the repo and was deleted locally
  after upload.
- `.gitignore` explicitly excludes `.env`, `.env.*` (except the example), service-account
  JSON, `.pem` and `.p12`. Only `.env.example` — which contains keys with no values — is
  tracked.

Verified by scanning full git history (`git log -S`) for the API key and for private-key
material, and by grepping the production bundle: neither appears in either.

### Rules and known gaps

- Firestore rules (`firestore.rules`) default-deny everything, scope each user to their
  own data, validate every field's type/enum/size, and make events, alerts, incidents
  and sessions append-only.
- **Linking is patient-initiated and consent-based.** A patient nominates a caregiver by
  email on their own profile; the caregiver is then recognised by their verified
  `auth.token.email`. A caregiver can never attach themselves to someone who didn't
  invite them, and revoking access is just removing the email.
- **Profile reads are scoped, not open.** `users/{uid}` is readable only by its owner or
  a nominated caregiver. Because rules are evaluated per document, a caregiver's
  `array-contains` query for their own email succeeds while an unconstrained listing of
  `/users` is denied — so the collection can't be enumerated and `emergencyContact` (a
  third party's name and phone) can't be harvested.
- No secrets in the repo. Client Firebase config comes from environment variables at
  build time; the Gemini key never reaches the client at all thanks to Firebase AI Logic.

**Known gaps**, called out deliberately rather than papered over:

1. **Firebase App Check is not configured.** Firebase AI Logic recommends it to stop
   unauthorized clients burning your Gemini quota. It's the first thing to add before any
   real-world release.
2. **Relapse snapshots live in Firestore as base64, not Cloud Storage.** That keeps the
   Spark plan viable and the read path rule-scoped, but a production build should move
   them to Storage with signed URLs and a retention policy.
3. **Live voice needs microphone permission and a modern browser.** No mic, or a browser
   without WebSocket/`getUserMedia` support, means falling back to the tap-only screen.

The rules are a solid first pass, not an exhaustively audited ruleset. They'd deserve
another dedicated review before this handled real patient data at scale.

---

## Assumptions and scope

- The caregiver's live view reflects one linked patient; there's no multi-patient or
  multi-caregiver management UI.
- Generated content is general wellness guidance — not a medical device, not a clinical
  assessment, and never mentions medication or dosages by design.
- Linking is one-directional and by email: the patient must have signed in at least once
  before a caregiver can link to them.
- Camera grounding only runs while a live voice session is open; there's no standalone
  camera mode.
