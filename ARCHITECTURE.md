# Architecture

Soter Recovery is two front-ends over one Firebase backend, split by who
uses them and where they are when they use it.

```
                    ┌──────────────────────────────┐
                    │   Firebase (recovery-        │
                    │   companion-hack)            │
                    │   Auth · Firestore · AI Logic│
                    └──────────────┬───────────────┘
                                   │
                ┌──────────────────┴──────────────────┐
                │                                     │
   ┌────────────▼─────────────┐        ┌──────────────▼──────────────┐
   │  PATIENT — Android app   │        │  CAREGIVER — web dashboard  │
   │  lib/ + android/ (repo   │        │  node-web/ (Vite + React +  │
   │  root, Flutter)          │        │  TS)                        │
   │                          │        │                             │
   │  Live voice + camera     │        │  Realtime activity stream   │
   │  Crisis interventions    │        │  Escalation alerts          │
   │  Emergency dialer        │        │  AI caregiver scripts       │
   └──────────────────────────┘        └─────────────────────────────┘
```

## Why this split

**The patient is in crisis, on a phone.** They need the mic and camera to work
reliably, the call to survive a screen-lock, and a one-tap dialer. That wants a
native app with real permissions and background execution — not a browser tab.
Android only for now; no iOS.

**The caregiver is monitoring, usually not in crisis.** They benefit from a
larger screen, history, and patterns over time. A web dashboard is the right
shape, and it's reachable from any device without an install.

## Patient app — Flutter, at the repo root (`lib/`, `android/`)

The Flutter app lives at the repository root — `lib/`, `android/`,
`pubspec.yaml` — rather than in a subfolder, since it's the primary,
actively-developed front end. The caregiver web app lives in `node-web/`
(see below).

- **Live voice:** `firebase_ai` Dart SDK, model
  `gemini-2.5-flash-native-audio-preview-12-2025`.
- **Important difference from the web SDK:** there is no Dart equivalent of
  the JS SDK's `startAudioConversation`, which did mic recording, playback
  scheduling, and barge-in for us automatically. The real Dart API is
  `LiveSession.sendAudioRealtime(InlineDataPart)` — one call per chunk, no
  stream-based framing helper — so the app owns mic capture
  (`lib/platform/audio/mic_capture.dart`), a native Kotlin `AudioTrack`
  playback engine (`android/.../audio/PlaybackEngine.kt`), and barge-in
  (server `interrupted` signal hard-flushes; a local energy-VAD hint only
  ducks volume). That layer being ours to build is the point — it buys real
  control over the device. See `DESIGN.md` §3 for the full design and
  `UX_AND_CLINICAL_GROUNDING.md` for the clinically-grounded conversation
  design.
- Camera frames for visual grounding, native permissions, emergency dialer.

## Caregiver dashboard — `node-web/` (React, deployed)

Live at https://recovery-companion-hack.web.app. Firestore `onSnapshot`
listeners mean the dashboard updates the moment something happens on the
patient's device — no reload. Run `npm install && npm run dev` from inside
`node-web/`, not the repo root.

**Not yet true today, stated plainly:** `node-web/src/App.tsx` still branches
on role and serves the *entire* original patient experience (live voice,
camera, tap-only fallback) alongside the caregiver dashboard, exactly as it
did before this split was decided — that code was never actually removed.
The caregiver-only split above is the target architecture, not the current
state of `node-web/`. Retiring the web app's patient path is planned once
the Flutter app's own live-call screen (still pending — M2 built the audio
pipeline, not the crisis-screen UI) is complete enough to fully replace it.

## Shared backend

One Firebase project, so both clients read and write the same documents.

- `users/{uid}` — profile, role, emergency contact, `linkedCaregiverEmails`
- `users/{uid}/events` — check-ins, interventions, live sessions
- `users/{uid}/alerts` — caregiver-facing scripts
- `users/{uid}/incidents` — relapse-risk records with a snapshot
- `users/{uid}/sessions` — transcripts, for cross-session memory

Linking is **patient-initiated**: the patient nominates a caregiver by email,
and the caregiver is recognised by their verified `auth.token.email`. A
caregiver can never attach themselves to someone who did not invite them. See
`firestore.rules`.

## Known constraint — no server push

The project is on the Spark (free) plan, so there are no Cloud Functions and
therefore **no server-sent push notifications**. A caregiver sees an escalation
in real time only while the dashboard is open.

Escalation currently relies on:
1. the patient's own device (native dialer / SMS to their emergency contact), and
2. the live dashboard when the caregiver has it open.

Making alerts reach a caregiver with the app closed requires FCM, which requires
Cloud Functions to send, which requires the Blaze plan. Documented here rather
than papered over.
