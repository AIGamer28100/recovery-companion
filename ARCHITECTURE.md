# Architecture

Recovery Companion is two front-ends over one Firebase backend, split by who
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
   │  mobile/  (Flutter)      │        │  src/  (Vite + React + TS)  │
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

## Patient app — `mobile/` (Flutter, Android)

- **Live voice:** `firebase_ai` Dart SDK, model
  `gemini-2.5-flash-native-audio-preview-12-2025`.
- **Important difference from the web SDK:** Dart exposes
  `session.startMediaStream(...)` and expects the app to own mic capture and
  audio playback. The JS SDK's `startAudioConversation` did recording, playback
  scheduling and barge-in for us. That layer is ours to build here — which is
  the point: it buys real control over the device.
- Camera frames for visual grounding, native permissions, emergency dialer.

## Caregiver dashboard — `src/` (React, deployed)

Live at https://recovery-companion-hack.web.app. Firestore `onSnapshot`
listeners mean the dashboard updates the moment something happens on the
patient's device — no reload.

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
