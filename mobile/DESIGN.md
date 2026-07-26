# Recovery Companion — Android App Design Document

Status: planning document, no application code written against it yet.
Scope: `mobile/` (Flutter, Android only). Backend, data model, and security
rules are shared with `src/` (the caregiver web dashboard) and treated as
fixed unless a genuine flaw is found (one is, in §5).

This document re-designs the patient experience for a native app rather than
porting the web build screen-for-screen. Where the web implementation
(`src/hooks/useLiveSession.ts`, `src/lib/geminiLive.ts`, `src/lib/liveTee.ts`,
`src/lib/videoStream.ts`, `src/lib/liveVad.ts`, `src/lib/safetyTools.ts`,
`src/lib/incidents.ts`) encodes a real, hard-won behavioral decision — VAD
tuning, motion-gated video, the relapse-risk tool contract — that decision is
preserved and carried into the Android design explicitly, with the reasoning
restated so it doesn't get silently dropped by an implementer who never read
the original.

---

## 1. UX / UI design

### 1.1 Identity: keep the ember, lose Material You by default

**Decision: carry the dark/ember identity to Android, deliberately. Do not
adopt Material You dynamic color as the default theme.**

Argument: this app is opened by someone who is often already dysregulated.
The visual identity's job is to be a **predictable landmark** — the same warm,
low-stimulation surface every single time, independent of what wallpaper is
on the phone that day. Material You's dynamic color extracts a palette from
the user's wallpaper and can hand you *anything*: a saturated red-and-white
scheme (visually adjacent to alarm/danger chrome, wrong tone for a grounding
tool), a low-contrast pastel that fails accessibility on the crisis screen, or
a palette that shifts every time they change their lock screen photo — which
is exactly the kind of small, meaningless novelty that erodes the "this place
is safe and always the same" feeling the ember design is going for on the web.
A native app earns the right to override platform defaults when the platform
default actively works against the product's job; this is one of those times.

Keep, ported to Flutter/Material 3 as a **fixed custom `ColorScheme`**, not the
dynamic one:

- `void` `#0A0A0B` — background
- `card` `#16150F` — elevated surfaces (sheets, transcript bubbles)
- `line` `#2A2823` — hairlines, borders
- `ink` `#F3F1EC` / `ink-muted` `#96938C` — text
- `ember` `#D69A52` — the single accent; used sparingly (CTA, live indicator,
  orb, focus rings) so it keeps its meaning ("something is active / this is
  the important thing") instead of becoming ambient decoration

Typography: bundle **Fraunces** (variable font, ship the `.ttf`/`.otf` in
`assets/fonts/`) for display text (headline on Home, "Recovery Companion"
wordmark) and the platform's default (Roboto Flex via Material 3's type
scale) for body/UI text. Do not set Fraunces on body copy — it's a display
face, and setting it small defeats the "plain language, plain type" tone the
system instruction asks the model to use in speech; the UI should match that
register in text too.

**Where the native app *should* diverge from the web, on purpose:**

- **Material 3 component shapes and motion curves** for anything that isn't
  bespoke (buttons, sheets, dialogs, switches) — fighting Material's own
  widgets to look exactly like Tailwind CSS components is wasted effort and
  produces a worse a11y story than just using `FilledButton`, `showModalBottomSheet`,
  etc. with a custom `ColorScheme`/`TextTheme` applied.
- **System back gesture / predictive back** must be respected properly
  (Android 13+ predictive-back preview) rather than the web's browser-history
  model — see §1.2 nav model.
- **A light theme must exist**, even though dark is the default and the
  primary crisis path is optimized for dark. Some users have photosensitivity
  or low-light-triggered discomfort in the *opposite* direction, or simply
  run their phone in forced light mode for other reasons (glare outdoors,
  visual impairment needing max contrast against a light ground). The web app
  is dark-only; the Android app should not be. Light theme: background
  `#FAF9F6`, ink `#1C1B18`, same ember accent (it has enough contrast against
  both). This is `ThemeMode.system` by default with a manual override in
  Settings, not `ThemeMode.dark` hardcoded like the current `main.dart`
  scaffold.

**Open question worth a real experiment, not a guess:** whether returning web
users expect literal visual continuity strongly enough that a divergent
Android type scale reads as "different app, do I trust it the same way."
Resolve with a 5-minute unmoderated test showing the Android Home screen next
to the web screen and asking "does this feel like the same thing." Don't
over-index on my aesthetic argument above without checking it against an
actual person who used the hackathon build.

### 1.2 Screen inventory and navigation model

No bottom navigation bar. A bottom tab bar bakes in "browsing between
sections" as the primary mental model, which is wrong here — there is one
job (talk to the companion, right now) and everything else is secondary and
should recede. Single-stack navigation via `go_router`, with the crisis path
reachable in at most one tap from anywhere the app is open.

```
Splash (auth check)
 ├─ Sign-in (Google Sign-In only — matches web; no email/password to build or secure)
 ├─ Onboarding (first run only, 3 screens, skippable after screen 1)
 │   1. What this is / what it isn't (see §5 medical-advice boundary)
 │   2. Emergency contact — optional but strongly prompted
 │   3. Link a caregiver by email — optional, explicit consent copy (§5.1)
 └─ Home  ──────────────────────────────────────────────────────────┐
     │  giant "Start talking" CTA, idle orb, minimal chrome           │
     │                                                                │
     ├─▶ Live Call (the crisis screen — detailed in §1.3)             │
     │     └─▶ Incident disclosure (non-dismissible on "escalated")  │
     ├─▶ Tap-only support (no-mic fallback; also reachable FROM        │
     │     the Live Call screen without ending the call's intent)     │
     ├─▶ Help now (bottom sheet, not a screen — emergency contact,     │
     │     public helplines, always one tap from Home AND from the    │
     │     in-call control pill)                                      │
     └─▶ Settings (menu icon, top-left, small target on purpose —      │
           this is the one place it's OK to require a deliberate tap)  │
           ├─ Emergency contact
           ├─ Linked caregivers
           ├─ Data & privacy (export / delete — see §5.2)
           ├─ Accessibility (text size preview, reduce motion, haptics)
           └─ Appearance (theme mode)
```

`History` (browsing past sessions) is explicitly **cut from v1** — see §8.

Route guard: `Splash → Sign-in` vs `→ Home` is driven by a `Riverpod`
`AsyncNotifier<User?>` over `FirebaseAuth.authStateChanges()`; `go_router`'s
`redirect` reads that provider so there's one source of truth for "am I
allowed here," not scattered `if (user == null)` checks per screen.

Predictive back: Live Call screen intercepts back navigation (`PopScope`)
and never exits silently mid-conversation — back always surfaces "End the
conversation?" rather than yanking the mic out from under a call. Every other
screen lets predictive back through untouched.

### 1.3 The crisis screen, in detail

This is used one-handed, possibly by someone shaking, crying, or
dissociating. Design constraints, in priority order:

1. **One primary action visible at a time.** Never two calls-to-action of
   equal visual weight.
2. **Nothing requires precision.** Every tappable target ≥ 56dp (bigger than
   Material's 48dp minimum — this population's fine motor control cannot be
   assumed at baseline).
3. **Nothing requires reading.** The screen must be operable by sound and
   shape alone; text is a backup channel (live captions), not the primary one.
4. **The one destructive-feeling action (end call) is never adjacent to the
   one urgent action (help now)** — a shaking hand fat-fingering "end call"
   when they meant "get help" is a real failure mode.

```
┌─────────────────────────────────────┐
│ ≡                              ●LIVE │  ← menu (56dp target, top-left,
│                                       │    reachable by thumb on large       
│                                       │    phones held one-handed low)       
│         Recovery Companion           │  ← Fraunces, quiet, not shouting
│                                       │
│      "I'm listening. Cut in          │  ← current-state line, changes with
│         any time."                   │    status (idle/connecting/live/     
│                                       │    camera-on/error) — always plain   
│                                       │    language, never a code or spinner-
│                                       │    only state                        
│                                       │
│                                       │
│           ╭───────────╮              │
│          ╱   ◉◉◉◉◉◉◉   ╲             │  ← breathing orb. Amplitude/speed
│         │   ◉  ●●●  ◉   │             │    driven by output-audio activity,
│          ╲   ◉◉◉◉◉◉◉   ╱             │    not a generic pulse — see §1.4
│           ╰───────────╯              │
│                                       │
│                                       │
│   [optional caption, last ~2 lines   │  ← live transcript, OFF by default,
│    of transcript, toggle in ≡]       │    toggle in Settings > Accessibility;
│                                       │    ON by default only if TalkBack/    
│                                       │    large-text is detected at launch  
│                                       │
│  ┌─────────────────────────────┐    │
│  │   🎥        ⛔        ⋯      │    │  ← control pill: camera toggle (56dp),
│  │  camera   END CALL   more    │    │    end call (72dp, red, CENTER —      
│  └─────────────────────────────┘    │    hardest to hit by accident, easiest 
│                                       │    to hit on purpose), overflow      
│         [Help now ↑]                 │    (tap-only fallback + help sheet)   
└─────────────────────────────────────┘    ← Help now: persistent, low-       
                                              contrast pill just above the      
                                              pill row, thumb-reachable,        
                                              always present even mid-call
```

Camera-on state: video fills the screen (mirrored, like the web), the orb
fades out entirely rather than floating over the person's own view of
themselves (ported directly from `ReactiveOrb`'s `cameraOn` collapse — that
decision is right on mobile too, arguably more so on a small screen where an
overlaid orb would cover more of the frame proportionally). A live-recording
affordance (small pulsing red dot + "camera on" label, top-right, outside the
video-scrim gradient) stays visible for the entire time the camera streams —
this is non-negotiable given the privacy surface in §4.3, and doubles as the
in-app answer to "is this actually still recording."

Incident disclosure (`flagRelapseRisk` fired): a banner slides up from above
the control pill, exactly where the web puts it. **Difference from web:**
on `stage="escalated"` the banner is **non-dismissible for 5 seconds** and
paired with a single medium-strength haptic pulse (not a startle-length
buzz) — the person must actually register "my caregiver was told" rather
than tap it away out of reflex the way you'd dismiss a cookie banner. On
`stage="intervening"` it behaves like the web (dismissible immediately) — no
haptic, since nothing external happened yet and a buzz here would just read
as the app being alarmed at them.

### 1.4 Motion and haptics — where they regulate, where they'd agitate

**Use haptics for:**

- **Breath pacing, opt-in, during a box-breathing exercise the model is
  leading.** A light `HapticFeedback.lightImpact()`-class pulse (Android:
  `VibrationEffect.createOneShot` with a low amplitude if
  `Vibrator.hasAmplitudeControl()`) at each phase change (inhale/hold/exhale/
  hold), driven by the *model's own spoken cadence* (parsed from output
  transcription timing, not a separately guessed 4-4-4-4 timer that could
  drift out of sync with what's actually being said). This is the one place
  haptics do real regulatory work — a felt rhythm is more reliable than a
  heard one when someone's ears are full of their own panic.
- **A single confirmation pulse** on call-connected and on entering the
  "escalated" incident banner (see above) — both are state changes the user
  must not miss even if they're not looking at the screen.
- **Nothing else.** No haptic on every transcript chunk, no haptic on camera
  toggle, no haptic on ordinary button presses beyond the OS default. Haptic
  noise trains the user to ignore haptics, which defeats the two cases above
  that actually matter.

**Avoid motion for:**

- Any screen transition faster/flashier than a plain cross-fade. No slide-in
  cards, no bouncy spring overshoot on the orb (the web's orb breathe/ring
  expand curves are `ease-in-out`/`ease-out` — keep that restraint, don't
  "improve" it with Material's springier defaults).
- **`MediaQuery.of(context).disableAnimations`** (Flutter's binding for
  system-level "remove animations" / iOS-style reduce-motion, driven on
  Android by Settings > Accessibility > Remove animations) must collapse the
  orb to a static glow and cut all page-transition animation to instant, not
  just "make it faster." Mirrors the web's `prefers-reduced-motion` handling
  in `index.css` — same intent, same seriousness.

### 1.5 Dark/light, dynamic type, touch targets

- `ThemeMode.system` default, manual override in Settings (§1.1).
- Support text scale up to Android's max (200%, via system Settings > Display
  size and text). At 200%: the crisis screen's control pill must **not**
  overflow horizontally — verified by putting text scale in scope for every
  golden test of that screen (§2.5), and by making the pill's labels
  icon+tooltip rather than icon+visible-label at high scale (icons don't
  reflow, labels do).
- Minimum touch target 56dp on the crisis screen, 48dp (Material default)
  elsewhere. Never smaller.
- One-handed reach: primary controls anchored to the **bottom** third of the
  screen everywhere (matches the web's bottom control pill), because that's
  the zone a thumb reaches without regripping the phone. The one deliberate
  exception is Settings access (top-left) — that's supposed to take a
  deliberate two-handed reach; it's not a panic-path control.

### 1.6 Empty, loading, error, and offline states — written in the app's voice

The system instruction's own register ("talk like a real person on a call...
plain language") is the bar for UI copy too. No error codes, no "Something
went wrong," ever, without a next step attached.

| State | Copy |
|---|---|
| First launch, no emergency contact set | "You don't have anyone set as your emergency contact yet. Want to add one now? You can always change it later." (Settings deep-link, dismissible, never blocking) |
| Connecting | "Opening the line…" *(matches web verbatim — it's plain and calm)* |
| Mic permission denied | "I need your microphone to talk with you. You can still use tap-only support without it — or turn it on in Settings whenever you're ready." *(never a bare OS permission-denied dialog with no app-side context)* |
| Camera permission denied, camera requested mid-call | "Camera's off — that's fine, I'm still right here. We can keep going by voice." |
| Network lost mid-call | "We got disconnected for a second — trying to get back to you…" then, if reconnection fails after retries: "The line dropped and I can't get back to you right now. Try again, or use tap-only support — it works without a connection." *(never leaves a silently-frozen "LIVE" badge — see §7.2)* |
| Weak connection detected before starting | "Your connection looks weak right now — the call might cut out. Want to try anyway, or use tap-only support instead? That one works offline." |
| Truly offline | Live call button disabled with inline note: "No connection right now. Tap-only support still works — it's on your phone, not the internet." Tap-only screen and the emergency dialer remain fully available (§7.1). |
| Empty transcript (call just started) | No placeholder text at all — an empty caption area is correct and calm; do not fill it with "Say something to get started." |
| Settings: no linked caregiver | "Nobody's linked yet. Linking a caregiver means they'll be told if things get serious — you're always in control of who that is." |

### 1.7 Accessibility

- **TalkBack**: every icon-only control has a `Semantics`/`tooltip` label
  written the way you'd say it out loud ("End the conversation", not "End
  call button"). The orb is `excludeSemantics: true` (it's decorative — the
  state line above it already says the same thing in words). Live
  captions default **on** when TalkBack is detected active
  (`MediaQuery.of(context).accessibleNavigation`), since a screen-reader user
  needs the text channel far more than a sighted hearing user does.
- **Reduced motion**: covered in §1.4.
- **Contrast**: `ink` on `void` is ~15.6:1 (WCAG AAA); `ember` on `void` is
  ~7.8:1 (AAA for large text, comfortably AA for body) — keep both ratios
  when the light theme is built (verify with the same tool, don't assume
  swapping background/ink preserves it).
- **One-handed reach**: covered in §1.3/§1.5.
- **Large font layout**: no fixed-height containers around text; the control
  pill and banners use `Wrap`/flexible sizing, not fixed `SizedBox`, verified
  by golden tests at 100%/150%/200% text scale (§2.5).

---

## 2. App architecture

### 2.1 State management: Riverpod

**Recommendation: Riverpod (with code generation via `riverpod_generator`),
not Bloc, not plain `Provider`/`setState`.**

Justification specific to this app, not a generic preference:

- The live-session pipeline is exactly one long-lived, app-wide-relevant
  piece of mutable state (mic stream, playback queue, socket, camera stream,
  incident flags) that must **survive widget rebuilds and even brief
  navigation** (e.g. opening the "Help now" sheet must not tear down the
  call). Riverpod's `Notifier`/`AsyncNotifier` with `ProviderScope`-level
  lifetime models this directly as a singleton-scoped controller without a
  hand-rolled service locator or `InheritedWidget` plumbing.
- Firebase's own APIs are stream-shaped (`Stream<QuerySnapshot>`,
  `Stream<User?>`) — `StreamProvider`/`AsyncNotifier` map onto that with
  near-zero adapter code.
- Testability is a stated requirement: Riverpod lets every repository and
  the entire audio pipeline be swapped for a fake via `ProviderScope(overrides:
  [...])` in widget/integration tests, with compile-time checking that
  nothing was missed (`Bloc` needs the same discipline but with more
  ceremony — separate `Event`/`State` classes per feature — for a project
  this size that's overhead without payoff). Plain `Provider`/`setState`
  can't cleanly express "this state must outlive this screen," which is the
  actual hard requirement here.
- Riverpod's compile-time-safe DI catches "provider not found" at analysis
  time in most cases, which matters more here than usual: a silently-missing
  audio controller on the crisis screen is not an acceptable failure mode.

### 2.2 Folder structure

```
lib/
  main.dart                     # bootstrap only: Firebase.initializeApp, runApp
  app.dart                      # MaterialApp.router, theme, ProviderScope
  core/
    theme/                      # ColorScheme, TextTheme, motion tokens
    router/                     # go_router config + redirect guards
    errors/                     # typed failures (no raw exceptions crossing layers)
  features/
    auth/
      data/                     # FirebaseAuth + Firestore profile repository
      application/               # AuthController (Riverpod)
      presentation/              # sign-in screen
    onboarding/
    home/
    live_session/
      domain/                   # SessionStatus, TranscriptLine, IncidentStage — plain Dart, no Firebase imports
      application/               # LiveSessionController (Riverpod Notifier) — orchestration, mirrors useLiveSession.ts's role
      data/                      # GeminiLiveRepository (wraps firebase_ai), IncidentRepository, SessionMemoryRepository
      presentation/               # Live Call screen + widgets (orb, transcript, control pill)
    tap_only/                   # offline-first fallback flow
    settings/
    help_now/                   # emergency contact + public helplines sheet, used from Home and in-call
  platform/
    audio/                      # the pipeline — see §3. Deliberately isolated: no Riverpod, no
                                 # Firestore imports in here. A package-shaped module with a narrow
                                 # Dart-facing API (AudioSession.start()/stop()/onBargeIn/...), backed
                                 # by a platform channel to Kotlin where needed.
    camera_stream/               # motion-gated frame streamer, mirrors videoStream.ts intent
    foreground_service/          # keeps the call alive through screen lock (§3, §6)
  widgets/                       # shared, generic (buttons, sheets) — no feature imports
test/
  features/...                  # mirrors lib/features structurally
  platform/audio/                # pure-Dart tests around framing/queueing logic, with a fake PCM source
```

### 2.3 Layering

`presentation (Widgets) → application (Riverpod Notifiers) → domain (plain
Dart models/use-cases, zero Firebase imports) → data (repositories that
wrap `firebase_ai`/`cloud_firestore`/platform channels)`.

Rule enforced by convention + a lint/CI check (grep for `firebase_ai`,
`cloud_firestore` imports outside `data/` and `platform/`): **no widget and
no Notifier ever imports a Firebase package directly.** Every touch point is
through an interface in `data/`, e.g.:

```
abstract class LiveSessionRepository {
  Future<LiveSessionHandle> connect();
}
```

so a fake can be substituted wholesale in tests — this is what makes the
audio pipeline (§3) testable at all, since you cannot practically run a real
Live API session in CI.

### 2.4 Where Firebase touches the app

- `firebase_core` — bootstrap only (`main.dart`).
- `firebase_auth` + `google_sign_in` — `features/auth/data`.
- `cloud_firestore` — one repository per collection family
  (`ProfileRepository`, `EventsRepository`, `IncidentsRepository`,
  `SessionMemoryRepository`, `AlertsRepository`), each a thin typed wrapper
  matching the schema documented in `firestore.rules` exactly — field names,
  allowed enums, and size limits duplicated as compile-time constants so a
  typo can't silently violate a security rule and fail at write-time with an
  opaque `PERMISSION_DENIED`.
- `firebase_ai` — `features/live_session/data/GeminiLiveRepository`, the
  **only** place `getLiveGenerativeModel`/`connect()`/`startMediaStream` are
  called. Model id, system instruction, VAD config, and the
  `flagRelapseRisk` tool declaration live here, ported from
  `geminiLive.ts`/`safetyTools.ts` — see §3 for exactly what changes in the
  port and what doesn't.

### 2.5 Keeping it testable

- **Unit tests**: domain logic (framing math, motion-gate threshold logic,
  transcript line-merging — the `appendTranscript` merge behavior in
  `useLiveSession.ts` is worth porting test-for-test) — pure Dart, no
  widgets, no Firebase.
- **Widget/golden tests**: Live Call screen at `{light, dark} × {100%, 150%,
  200% text scale} × {TalkBack semantics on/off}` — this is the concrete
  mechanism behind the "verified by golden tests" claims in §1.5/§1.7, not
  just an aspiration.
- **Fake audio pipeline** for widget tests: an `AudioSession` fake that
  emits synthetic PCM/transcript events on a controllable `Stream`, so
  barge-in and incident-banner UI logic can be tested without touching a
  real mic, real socket, or real device.
- **Integration test**: one happy-path flow (sign in → start call → receive
  a scripted fake serverContent stream → end call → verify Firestore writes)
  against the Firebase Local Emulator Suite, not production Firebase — keep
  this out of CI-blocking status initially if emulator setup for `firebase_ai`
  proves impractical (Live API emulation support should be verified early;
  if it doesn't exist, this becomes a manual pre-release checklist item
  instead, and that should be decided explicitly rather than silently
  skipped).

---

## 3. The live audio pipeline

This is the hardest part of the whole app and the reason `startAudioConversation`
not existing in the Dart SDK is a real design problem, not a minor gap. The
web SDK gave you mic capture, 24kHz playback scheduling, and barge-in for
free; here, all three are ours to build.

### 3.1 Pipeline overview

```
 MIC (device)                                          MODEL (Live API)
   │                                                          │
   ▼                                                          │
[record: startStream()]  16kHz mono PCM16, raw bytes          │
   │                                                          │
   ▼                                                          │
[Framer: 20ms frames → batch to ~100–200ms chunks]             │
   │                                                          │
   ▼                                                          │
[base64 encode] ──▶ session.startMediaStream(chunkStream) ──▶ │  outbound
                                                                │
                                                                ▼
                                        session.receive() ──▶ serverContent
                                                                │  (audio, 24kHz PCM16,
                                                                │   base64; text transcripts;
                                                                │   `interrupted` flag;
                                                                │   tool calls)
   ┌────────────────────────────────────────────────────────┘
   ▼
[base64 decode] → [Jitter buffer, ~2–3 frames / 120–200ms]
   │
   ▼
[Platform channel: AudioTrack, MODE_STREAM, 24000Hz, PCM16] ──▶ SPEAKER/HEADSET
   │
   ▲  on `interrupted` (server) OR local VAD hint (client, early) —
   └─ AudioTrack.pause() + AudioTrack.flush() + clear queued chunks
```

`teeSession` (`liveTee.ts`) has a direct Dart equivalent problem:
`LiveSession.receive()` will only support one consumer here too. Build the
same fan-out — a single internal loop over `receive()` that both feeds the
playback queue and mirrors every message to a `Stream<ServerMessage>`
consumed by the transcript UI and the tool-call handler. Don't let two
separate call sites call `receive()` independently; verify early whether the
Dart SDK's `receive()` even allows a second call (may throw, may silently
steal chunks like the web) — **name the experiment**: write the tee wrapper
first, in isolation, before anything else in this section, and confirm with
a two-consumer test that only one of them gets data absent the wrapper.

### 3.2 Mic capture and framing (outbound)

Use the `record` package's `startStream()` with `RecordConfig(encoder:
AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1, androidConfig:
AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication))`.
The `voiceCommunication` audio source (not the default `mic`) is the load-bearing
choice here — see §3.4 on echo cancellation; it's not just a "which enum
value" detail.

Framing: 16kHz × 16-bit mono = 32,000 bytes/sec = ~32 bytes/ms. Batch
`record`'s stream output into ~100–200ms chunks (3,200–6,400 bytes) before
base64-encoding and handing to `session.startMediaStream`. Rationale for the
batch size: smaller chunks (e.g. raw 20ms frames) mean lower latency per
frame but multiply message/base64 overhead and GC churn; much larger chunks
(500ms+) add perceptible mouth-to-model delay. 100–200ms is the same range
WebRTC-style systems converge on for this trade-off. **This needs validating
against real round-trip numbers once M2 (§8) is running — treat 150ms as a
starting point, not a final answer.**

**Verify before building further**: whether `LiveSession.startMediaStream`
takes a `Stream<Uint8List>` of raw PCM and does the base64 framing internally,
or expects pre-built `InlineDataPart`/base64 chunks. The prompt that
commissioned this document states the API shape as `session.startMediaStream(stream)`
without pinning the exact element type — resolve this against the installed
`firebase_ai: ^3.14.1` package source (`flutter pub cache`/pub.dev
documentation) in the first hour of M2, not by guessing here.

### 3.3 Playback (inbound) — gapless queue and why it needs a platform channel

Inbound audio is 24kHz PCM16, arriving as base64 chunks inside `serverContent`
messages via the tee described in §3.1. **Recommendation: a small Kotlin
platform channel wrapping `android.media.AudioTrack` in `MODE_STREAM`,
rather than a pure-Dart audio player package.**

Why not a Dart package (`just_audio`, `audioplayers`, etc.): those are built
around discrete, seekable media items (files, URLs, containers), not a
continuously-appended raw PCM stream that must start playing before all the
data exists and must be **flushable mid-buffer on barge-in with no audible
click or pop**. Wrapping raw PCM into WAV headers per chunk and feeding a
player queue is the kind of thing that technically works in a demo and then
produces audible seams/pops at every chunk boundary in real use — exactly
the failure mode ("feels broken") called out as highest risk in §9. Direct
`AudioTrack.write()` calls into a stream-mode track, with a app-owned ring
buffer feeding it, gives real control over:

- **Flush-on-interrupt**: `AudioTrack.pause()` → `AudioTrack.flush()` →
  clear the Dart-side queued-chunk buffer → `AudioTrack.play()` resumes clean
  for the next utterance. This is the actual mechanism behind barge-in (§3.5)
  — there is no way to get this precise a stop-and-discard from a
  container-based player.
- **Buffer sizing** tuned independently of whatever a generic package
  assumes (`AudioTrack.getMinBufferSize()` plus a deliberate small multiple
  for jitter tolerance — see §3.6).
- **`AudioAttributes`** set to `USAGE_VOICE_COMMUNICATION` /
  `CONTENT_TYPE_SPEECH`, which pairs with the `voiceCommunication` mic source
  from §3.2 to get OEM-level AEC/NS pairing between record and playback
  endpoints (§3.4) — a generic media player defaults to `USAGE_MEDIA`, which
  does not get this pairing.

This is explicitly flagged as **requiring a platform channel** per the task's
instruction to name such things — it is not optional scaffolding, it's the
core of why this section is hard.

### 3.4 Echo cancellation — not hearing itself

Two layers, both necessary:

1. **Symmetric audio source/attributes**, as above: `AndroidAudioSource.voiceCommunication`
   on the recorder and `AudioAttributes(usage: USAGE_VOICE_COMMUNICATION,
   contentType: CONTENT_TYPE_SPEECH)` on the `AudioTrack`. On most OEM
   builds this is what causes the platform's built-in AEC/NS/AGC audio
   effects to actually engage and pair the input/output streams — it does
   **not** happen automatically just because both exist independently.
2. **Explicit `AcousticEchoCanceler` check**, via platform channel:
   `AcousticEchoCanceler.isAvailable()` — the `record` package does not
   expose this. Where available, explicitly instantiate and enable it bound
   to the active `AudioRecord` session ID. Where unavailable (some
   budget/older devices genuinely lack hardware AEC), **fall back to muting
   local mic capture for the duration of model audio playback** — an
   imperfect but safe fallback that trades "can't barge in during this
   utterance on this specific device" for "the model never hears and
   responds to itself." This fallback path needs a device flag surfaced to
   the UI (a subtle "tap to interrupt" affordance replacing true barge-in
   when AEC is unavailable) so the UX doesn't just silently degrade.

**Also both sides must be in `AudioManager.MODE_IN_COMMUNICATION`** (not
`MODE_NORMAL`) for the pairing above to take effect on many devices — set
this when the call starts, restore `MODE_NORMAL` when it ends. This is
exactly the kind of Android platform-mode detail that's invisible until you
test on a real device and hear yourself echo back — **flag as a required
real-device test item in M2/M6, not something to trust from documentation
alone.**

### 3.5 Barge-in

Two signals, one authoritative:

- **Authoritative: the server's own interruption signal.** The Gemini Live
  API sends an `interrupted` indicator on `serverContent` when its own VAD
  detects the user speaking while the model is still generating/streaming
  audio. On receipt: immediately flush the playback pipeline (§3.3) and
  discard any not-yet-played queued chunks for the utterance in flight. This
  is correct by construction — it's the same signal the model itself used to
  decide to stop.
- **Early client-side hint, not authoritative:** a lightweight local
  energy-based VAD on the outbound mic stream, active only while the model
  is speaking, used **only to duck local playback volume slightly** (not to
  flush) the moment the user starts talking, closing the perceptual gap
  before the server's `interrupted` round-trips back. Ducking rather than
  hard-flushing on the client-only signal avoids a false-positive flush from
  breathing, a cough, or echo bleed-through cutting the model off
  incorrectly — the hard flush stays reserved for the server's confirmed
  `interrupted` signal.

This mirrors the intent of `liveVad.ts`'s server-side VAD tuning
(`silenceDurationMs: 1400`, `endOfSpeechSensitivity: 'END_SENSITIVITY_LOW'`,
etc.) — **port that exact `realtimeInputConfig` block** into the Dart setup.
The web app had to monkey-patch `WebSocket.prototype.send` because
`@firebase/ai`'s `LiveModelParams` didn't surface `realtimeInputConfig`
directly. **Check first** whether `firebase_ai: ^3.14.1` (a different,
possibly newer SDK generation) exposes this natively — if it does, this is a
clean config pass-through with no workaround needed; if it doesn't, the same
class of workaround (intercepting the outbound setup frame at the transport
layer, if that's even reachable from Dart) will be needed and should be
scoped as its own spike rather than discovered mid-integration.

### 3.6 Buffer sizing and latency budget

Target end-to-end **added latency budget** (excluding model think-time and
network RTT, which aren't ours to control): **300–500ms one-way**, mic-to-
network-send. Breakdown:

- Mic frame batching: 100–200ms (§3.2)
- Encode/base64/send overhead: ~10–30ms
- Playback jitter buffer: 2–3 chunks held before starting playback
  (~120–200ms at 24kHz chunking) to absorb network jitter without audible
  stutter — too small and you get underrun glitches, too large and the
  model feels laggy to interrupt.

These are starting numbers to validate against a stopwatch in M2 (§8), not
numbers to trust blind — call this out explicitly in the M2 definition of
done.

### 3.7 Phone call interruption

Use the **`audio_session`** package (new dependency — not in the current
`pubspec.yaml`; add it) to request audio focus (`AndroidAudioFocusGainType.gain`)
when a call starts. On `AudioFocusLoss` (an actual incoming/active phone
call takes focus): pause mic capture and playback immediately, keep the Live
API socket open for a short grace window (~30–60s) rather than closing it
outright — phone calls in this population are frequently short or declined —
and if focus isn't regained within the window, close the session gracefully
and show the "line dropped, want to try again?" state from §1.6. On
`AudioFocusLossTransient` (shorter interruptions, e.g. a notification sound
claiming focus briefly), auto-resume without ending anything.

Also handle **"becoming noisy"** (`audio_session`'s `becomingNoisyEventStream`,
backed by Android's `ACTION_AUDIO_BECOMING_NOISY`) — fires on headphone
unplug. Pause playback immediately on this event rather than let the
conversation suddenly blast out of the speaker; this matters doubly here
since a plausible reason someone had headphones in during this exact
conversation is privacy from people around them.

### 3.8 Bluetooth and wired headset routing

Wired headsets: handled by the OS/AudioTrack routing automatically once
`audio_session`'s communication-mode configuration is active — no extra work
expected.

Bluetooth: **flagged as a real risk, not a solved problem** (see §9, R10).
Routing *output* (model's voice) to a connected BT audio device should work
through standard Android audio routing once in communication mode. Routing
*input* (the user's mic) through a BT headset requires actively starting
Bluetooth SCO (`AudioManager.startBluetoothSco()`) — `record`'s and
`audio_session`'s Android coverage of SCO control should be verified early
rather than assumed; if neither exposes it adequately, that's another
platform-channel candidate. BT SCO audio is also narrowband (8kHz, well
below the 16kHz the model expects), which either needs upsampling before
send or acceptance of reduced input quality over Bluetooth mic specifically.
**Recommendation: ship BT for output only in v1** (model's voice can go to a
BT speaker/earbuds; mic stays on the phone's own microphone even with BT
connected) — cut the BT-mic-input case from v1 rather than risk shipping a
flaky, hard-to-test-in-CI audio path (§8).

### 3.9 Foreground service — surviving screen lock and backgrounding

Not in the current dependency list — **flag as a required new addition**:
either the `flutter_foreground_task` package, or a small hand-written native
Android foreground service reached via platform channel. Without this,
Android will suspend mic access within seconds of the app losing foreground
visibility (screen lock, task-switch to another app), silently killing the
call the person is relying on.

Concrete requirements:

- Foreground service declared with `foregroundServiceType="microphone"` (and
  `"camera"` while the camera is actively streaming — camera specifically is
  much more restricted in the background than mic on stock Android; see §6).
- Android 14+ requires this type declaration explicitly and enforces it;
  build and test against a real Android 14/15 device, not just the emulator,
  before trusting this (§9, R2).
- Persistent notification (required by the OS for any foreground service)
  written in-voice: "Recovery Companion — still on the line" with a direct
  tap-back-into-the-call action and an end-call action, so the person can
  manage the call from the notification shade too.
- On screen lock specifically: mic + socket continue via the foreground
  service; camera goes dark (stock Android does not allow background camera
  access from a non-visible Activity, foreground-service type notwithstanding,
  in practice). Send a director-note-style message on the session the moment
  this happens (mirroring the `toggleCamera` silent-note pattern in
  `useLiveSession.ts`) so the model knows to stop coaching visually and say
  nothing about the camera rather than confusingly narrate a scene it can no
  longer see.

### 3.10 Named packages and platform-channel summary

| Concern | Package / API | Platform channel needed? |
|---|---|---|
| Mic capture, 16kHz PCM16 stream | `record` (already added) | No, if `voiceCommunication` source works as documented — verify early |
| Framing/batching | Pure Dart | No |
| Session I/O | `firebase_ai` (already added) | No |
| Playback (24kHz, flushable, gapless) | `android.media.AudioTrack` | **Yes** — core of §3.3 |
| AEC explicit control | `android.media.audiofx.AcousticEchoCanceler` | **Yes** |
| Audio focus / interruptions / becoming-noisy | `audio_session` | **New dependency**, no channel expected |
| Foreground service (screen lock survival) | `flutter_foreground_task` or hand-written | **New dependency or a channel** |
| Bluetooth SCO (mic input) | — | Cut from v1 (§3.8) |
| Camera frames | `camera` (already added) | No |
| Thermal status | `android.os.PowerManager` | **Yes** (§4.4) |
| Biometric app lock | `local_auth` | **New dependency** (§5.4) |

---

## 4. Camera & vision

### 4.1 Frame capture cadence — motion-gating still holds, tuned for mobile

`videoStream.ts`'s core idea — send a keyframe every ~6s and otherwise only
send a frame when the scene has actually changed, measured cheaply via a
downsampled luminance diff — **is still the right call on mobile, and
arguably more important here**: mobile has real battery/thermal/metered-data
costs that a browser tab mostly externalizes to the desktop it's running on.

Changes for the mobile port:

- **Tick interval**: widen from the web's 1000ms to **1500–2000ms**. Phone
  camera pipelines (sensor → ISP → app buffer) cost more CPU per frame
  pulled than a browser's `drawImage` from an already-decoded `<video>`
  element; a slightly coarser tick trades negligible responsiveness for
  meaningfully less sustained CPU/thermal load.
- **Motion diff on the raw YUV plane, not an RGBA canvas.** `camera`'s image
  stream (`startImageStream`, `ImageFormatGroup.nv21` on Android) delivers
  frames with a Y (luminance) plane already separate from chroma — sample
  that plane directly with the same strided-read trick `videoStream.ts` uses
  (step by N, read one channel), skipping the RGBA conversion the web
  version needs, since canvas only gives it RGBA. Cheaper per frame than the
  web equivalent, which helps justify keeping the wider battery margin from
  the tick-interval change rather than needing it.
- **Don't stop/restart the image stream to save power.** `startImageStream`/
  `stopImageStream` has real overhead and latency; instead, run the stream
  continuously while the camera is on and **discard** frames on ticks that
  don't need to be evaluated, rather than starting and stopping the pipeline
  per tick.
- **Resolution**: request `ResolutionPreset.low` (~240p) or `.medium`
  directly from `CameraController`, rather than the web's approach of
  capturing high-res and downscaling to 512px width in a canvas — asking the
  sensor for less data in the first place is strictly cheaper than
  discarding it after capture. Keep the JPEG quality in the same range as
  the web (~0.5–0.6) for the frame that's actually sent.
- **Keyframe interval**: keep at ~6s, matching the web — no reason to
  diverge; it was already tuned against the same underlying model-context
  problem (`contextWindowCompression`) that applies identically here.

### 4.2 What doesn't change

The reasoning in `videoStream.ts`'s comments about *why* motion-gating
exists — a naive fixed-rate stream piles near-identical frames into the
model's context and response latency creeps up the longer a still scene
runs — is a property of the model's context handling, not the browser, so
it applies unchanged on Android. Port the actual threshold logic
(`MOTION_THRESHOLD`), then **re-tune the constant against real on-device
measurements** rather than assuming the web's `6` transfers directly — the
luminance sampling path is different enough (YUV Y-plane vs RGBA red
channel) that the numeric threshold may need recalibrating. Name this as an
experiment for M4 (§8), not a copy-paste.

### 4.3 Thermal and battery impact

Continuous mic + continuous camera + continuous network + screen-on is a
genuine sustained-load profile on a mid-range Android phone, and this
population may be using a lower-end device. Add an explicit thermal
guardrail not present in the web app (a browser has no comparable API):
platform-channel access to `PowerManager.getCurrentThermalStatus()` /
`addThermalStatusListener` (API 29+). On `THERMAL_STATUS_SEVERE` or above,
proactively **degrade to audio-only** (stop the camera stream, tell the
person plainly via a UI banner and let the model know via a director note
that mirrors the manual-camera-off path already designed for
`toggleCamera`) rather than letting the OS throttle the app unpredictably or
kill it outright. This is a case where doing something visible and graceful
beats doing nothing and hoping.

### 4.4 Privacy surface of streaming someone's room

This is the single largest privacy exposure in the whole app: the camera can
see inside someone's home during what may be their most compromising
moment — visible substances, other people (including minors) who never
consented to anything, a messy or embarrassing space, physical
self-harm indicators. Design responses:

- **Camera is opt-in per session, every time.** No "remember my choice and
  auto-start next time." The web already gets this right (`cameraOn` starts
  `false` every session) — preserve it exactly; do not "improve" it with a
  persisted preference.
- **Visible recording indicator beyond the OS one**, as specified in §1.3 —
  the OS's own camera-in-use dot is easy to miss when someone's attention is
  elsewhere; the in-app indicator is a deliberate second layer.
- **Frames are ephemeral** — sent live to the model and never written to
  device storage or Firestore, with exactly one exception: the single
  evidence snapshot captured at the moment `flagRelapseRisk` fires (§5.1),
  which is a deliberate, disclosed departure from "ephemeral," not an
  accident, and must be treated with the weight that implies.

---

## 5. Security, privacy & safety

Treated here as a duty of care. Several places below say plainly that the
current (web-inherited) design is ethically thin — that's intentional; a
design document that only validates existing choices isn't doing its job.

### 5.1 Consent — two distinct kinds, both must be explicit and revisited

1. **Consent to record (mic/camera) during a live session.** Session-scoped,
   re-affirmed by the act of tapping "Start talking" / turning the camera on
   each time — not a one-time install-time checkbox. The OS permission
   prompt is not sufficient consent UX on its own; it explains *what* is
   being accessed, not *why* or *what happens to it*, so it's preceded by
   the app's own plain-language priming screen (§1.2, onboarding step 1, and
   again the first time camera is requested specifically).
2. **Consent to caregiver reporting and relapse-snapshot capture — the
   ethically heaviest thing in this product.** An AI deciding, on its own
   judgment, to capture a photo of someone during active substance use and
   flag it to a third party is a real surveillance act, however
   well-intentioned. This must be:
   - **Explained in specific, concrete language at the moment a caregiver is
     linked**, not buried in a general privacy policy — proposed copy:
     *"If your companion sees on camera that you've started using, it will
     try to talk you through it first. If you continue anyway, it saves a
     photo to your own record and lets [caregiver name] know — even in the
     moment, even if you don't want it to right then. You're choosing that
     now, in advance, for the times you might not want it in the moment."*
     This should be read back to them, not just displayed as fine print, and
     require an explicit affirmative tap, not a pre-checked box.
   - **Revocable at any time** from Settings (unlink caregiver → this
     specific consequence stops applying going forward).
   - **Disclosed in the moment it happens**, unmissable — the non-dismissible
     escalated-incident banner design in §1.3 is the enforcement mechanism
     for this promise, not just a UI nicety.

### 5.2 Data retention and deletion — flagged as genuinely thin today

`firestore.rules` currently sets `allow update, delete: if false` on every
subcollection (`events`, `alerts`, `incidents`, `sessions`). That means
**there is no deletion path at all, for anyone, including the patient
themselves, for their own relapse-evidence photo.** That's defensible as an
anti-tampering measure against a caregiver or the patient quietly erasing an
inconvenient incident — but as currently built it also means someone in
recovery has zero ability to ever reclaim narrative control over a captured
moment of relapse, permanently. That tension is real and worth stating
plainly rather than resolving it by silent omission.

**Decided (product owner, [date of this review]): stay fully immutable.**
No delete path, for anyone, ever — including the patient, including their
own relapse-evidence photo. The self-delete-with-tombstone option below was
considered and explicitly rejected: anti-tampering integrity of the
caregiver-facing record wins over patient-side erasure. This is a conscious
call, not an oversight — do not silently add a delete path later without
revisiting this decision explicitly.

What ships instead, scoped to what's buildable on Spark (no Cloud Functions):

- **Firestore TTL policies** (a native Firestore feature, not a Cloud
  Function, available on the free/Spark tier) on `incidents`, `sessions`,
  and `events` — add an `expiresAt` timestamp field (e.g. `createdAt + 180
  days`) at write time and configure a TTL policy on that field. This is the
  **only** retention control in v1: automatic, defensible, time-bounded
  expiry, without touching the append-only integrity property. **M7 item.**
- **A data-export path** (Settings > Data & privacy: "Download everything
  we have about you") — straightforward client-side Firestore reads
  bundled into a shareable file, no backend needed, and a meaningful
  trust-building feature independent of the immutability decision above.

*(Rejected option, recorded for context: a narrow self-delete path for the
patient on their own incidents, paired with a tombstone/audit counter on the
profile doc so a caregiver relationship isn't silently undermined without
trace. Revisit only via an explicit, conscious product decision — not a
future implementer's unilateral call.)*

### 5.3 Android-specific concerns

- **`FLAG_SECURE`**, applied narrowly to the Live Call screen and any
  incident-detail view (not the whole app) — blocks screenshots, screen
  recording, and app-switcher thumbnail capture of exactly the two places
  that could expose either a live conversation or a relapse-evidence photo.
  Confirmed non-conflict: `FLAG_SECURE` does **not** block TalkBack or other
  accessibility services from reading screen content — it only blocks pixel-
  level capture (screenshot/cast/recording), so this is safe to apply without
  an accessibility trade-off.
- **Local caching of evidence photos**: `cloud_firestore`'s offline
  persistence is **on by default** and will write incident documents —
  including the embedded base64 JPEG — into an on-device SQLite cache for
  offline read/sync support. This is a real, currently-undisclosed exposure:
  anyone with physical access to an unlocked (or forensically-imaged) device
  can potentially read that cache outside the app entirely. Recommendation:
  either disable persistence specifically for the `incidents` collection
  path (if the SDK allows path-scoped persistence control; verify — Firestore's
  offline persistence is typically all-or-nothing per `FirebaseFirestore`
  instance, which may mean this isn't cleanly separable, and the fallback is
  documenting the exposure and leaning on device-level encryption + the
  biometric lock below rather than a false sense that the cache is scoped
  safely) or clear the local cache (`clearPersistence()`) on sign-out.
- **Biometric/PIN app lock** — **not in the current dependency list; add
  `local_auth`.** Given the realistic threat model for this population (a
  partner, parent, or roommate picking up an unlocked or easily-guessed
  phone is a materially more likely threat than a remote attacker), an
  optional but strongly-encouraged app-level biometric gate — at minimum in
  front of Settings and any incident detail — is worth the implementation
  cost. Recommend defaulting it **on** after the first caregiver is linked
  (that's the moment sensitive evidence starts accumulating) rather than
  leaving it opt-in and probably never turned on.
- **App Check**: enable Firebase App Check with the **Play Integrity**
  provider on the Android app. This is what stands between "no API key ships
  in the client" (already a stated hard constraint) and a repackaged/
  tampered APK still being able to hit the Gemini Live endpoint through
  Firebase AI Logic freely. Concrete setup step: register the app's release
  signing certificate's SHA-256 with the Play Integrity API console entry —
  call this out explicitly as a release-blocking checklist item (§8, M7),
  since it's easy to forget until a debug build "just works" and a release
  build silently doesn't.

### 5.4 The medical-advice boundary

The existing system instruction already does real work here ("Never mention
medication or dosages," "gently encourage them to contact emergency services
or a crisis line"). Two gaps worth naming:

- **No persistent, always-reachable disclaimer in the app itself** —
  currently this boundary lives entirely inside the model's system prompt,
  invisible to the user. Add a short, honest line to onboarding step 1 and
  make it permanently reachable from Settings: *"This isn't a doctor, a
  therapist, or a replacement for treatment. It's here to help you get
  through a hard moment. If you're in a medical emergency, call [112 /
  regional emergency number]."*
- **Self-harm/suicide handling relies entirely on the model's in-the-moment
  judgment, with no deterministic backstop.** The system instruction says
  the model should "gently encourage" contacting a crisis line "if they seem
  to be in immediate danger" — that's a real signal to preserve, but it's
  the only line of defense today, and the cost of the model missing a cue
  once is categorically higher than most other failure modes in this app.
  **Recommendation**: add a client-side, non-model, keyword/pattern check
  over the live *output* transcript (not the input — acting on what the
  *model* said avoids putting words in the user's mouth) that, on matching a
  small curated list of self-harm/suicide-adjacent terms the model itself
  used, automatically surfaces the "Help now" sheet on-screen (not
  interrupting audio, not claiming to have detected anything to the user —
  just making the escape hatch more visible exactly when it's statistically
  more likely to matter). This is a deterministic safety net underneath a
  probabilistic system, not a replacement for the model's own handling —
  name it plainly as a backstop, and treat any false positives as an
  acceptable cost given what a false negative would mean.

### 5.5 Where this design is still ethically thin — stated plainly

1. ~~No deletion path for the patient's own relapse evidence today~~ —
   **decided (§5.2): stays fully immutable, TTL-only retention.** No longer
   an open item; recorded here so the decision and its rationale stay visible
   rather than looking like an oversight to a future reader.
2. Self-harm/suicide handling has no deterministic backstop in the current
   (web-inherited) design (§5.4) — proposed fix above, not yet built
   anywhere.
3. The relapse-snapshot-and-alert feature is a real trust risk: if a person
   feels *watched* rather than *supported*, they may simply stop being
   honest with the companion, or stop using the app during the exact moments
   it exists for. There is no mechanism today for the patient to add their
   own context to an incident after the fact ("I want my caregiver to know I
   put it down again 20 minutes later") — worth considering for a future
   version, explicitly out of scope for v1 here.
4. Public helpline numbers are hard-coded India-only (`emergencyContacts.ts`
   already flags this in its own comment) — shipping this anywhere else
   without re-verifying and localizing those numbers is actively dangerous,
   not just an incompleteness.
5. The Firestore offline-cache exposure of evidence photos (§5.3) doesn't
   have a clean fix within current SDK capabilities as far as this review
   determined — flagged rather than papered over.
6. §5.6's account-deletion design cannot automatically remove the empty
   Firebase Auth record on Spark (no Admin SDK/Cloud Function) — a small,
   disclosed residual gap, not silently left unmentioned.

**Compliance disclaimer, stated once here rather than repeated per
subsection:** §5.6 below is a good-faith engineering interpretation of GDPR
Articles 17 (erasure) and 20 (portability), not legal advice. Get real legal
review before relying on this design as a compliance claim to real users —
particularly the interaction between Article 17(3)'s exemptions and this
product's own anti-tampering rationale for relapse evidence, which is a
genuine tension, not a solved one (see §5.6.1).

### 5.6 Account deletion (right to erasure) and data export (right to portability)

This section was not commissioned by the original design brief and is a
later addition — added deliberately at design time, before any Settings
screen exists, rather than retrofitted after ad hoc deletion code has
already shipped somewhere.

#### 5.6.1 Reconciling with §5.2's immutability decision

§5.2 decided that a single incident can never be deleted by anyone, ever —
that decision **stands, unchanged, for the lifetime of an active account**.
Full account deletion is not a loophole around it; it is a different,
much larger, formally-gated action, and the two are meant to coexist like
this:

- §5.2's concern was a patient (or a compromised session) quietly erasing
  *one inconvenient incident* while the account and the caregiver
  relationship stay active — that would let evidence disappear while the
  reason it existed (an active relationship built on the promise that it's
  visible) is unchanged. Still rejected, unconditionally.
- Closing the account ends that relationship *in its entirety*. There is no
  remaining relationship for isolated evidence to selectively survive
  under, and GDPR Article 17 gives the patient a real right to ask for all
  of it to go. Treating "delete everything, formally, with a 30-day
  cooling-off period" as categorically different from "quietly delete this
  one photo, right now, no one else asked" is the load-bearing distinction
  here — not a contradiction of §5.2, an application of it.
- The security-rules design below enforces this distinction mechanically,
  not just in prose: the narrow update permission that lets a client touch
  an otherwise-immutable document's expiry is only granted **after** the
  account-wide deletion has been formally requested (checked via a `get()`
  on the parent profile doc), and it can only ever set the expiry to the
  *account's* scheduled date — never an arbitrary earlier date on a single
  document in isolation. There is still no way to delete just one incident.

#### 5.6.2 Why Firestore TTL, not a timer anyone has to run

The Spark plan has no Cloud Functions, so there is no server-side cron to
"come back in 30 days and actually delete this." **Firestore's native TTL
(Time-to-Live) policies are the mechanism** — a per-collection-group policy
on a timestamp field that the Firestore backend itself sweeps and deletes
from, without any app code, Cloud Function, or the client needing to be
online when it fires. It is a free, Spark-plan feature, and — importantly —
**TTL deletions are performed by the Firestore backend outside of Security
Rules evaluation**, so no `allow delete` needs to be granted to any client
at all. The client's only job is to write the correct expiry date onto the
right documents; the actual deletion is something no client, including the
account owner's own, ever has permission to trigger directly.

This composes with M7's separate, already-planned 180-day general-retention
TTL (§5.2) on the **same `expiresAt` field**: general retention sets
`expiresAt = createdAt + 180d` at write time as the default; requesting
account deletion simply **overwrites** that field to the earlier
account-wide date on every existing document. Whichever value is smaller
wins, naturally, with no field-name conflict and no dual bookkeeping.
**Dependency, not just a suggestion for sequencing:** this feature requires
M7's `expiresAt`-at-creation-time change to already be live (every event/
alert/incident/session must already be written with an `expiresAt` field)
before deletion cascade logic has anything reliable to overwrite — build
order matters here.

TTL is not instant: Google documents Firestore TTL deletions as typically
completing **within 24 hours of expiry, not to the second**. State this
honestly in the UI copy below ("within about 31 days," not "on day 30 at
midnight") — promising precision TTL doesn't provide is its own small
trust cost, and an easy one to avoid.

#### 5.6.3 The flow

1. **Settings → Data & Privacy → "Delete my account."** Explains, in the
   app's plain-language register, what happens and when: *"This deletes
   everything — your check-ins, conversations, and any saved photos —
   within about 31 days. You can change your mind and cancel any time
   during that window just by signing back in. After that, it's gone for
   good, including from your caregiver's view."*
2. **Re-authentication required** (`reauthenticateWithProvider` via Google
   Sign-In) before the request is accepted — this is a Firebase requirement
   for sensitive Auth operations on an account whose sign-in is not
   freshly established, and it's the right friction for an irreversible-
   after-the-window action regardless.
3. **On confirm, the client:**
   - Writes `deletionRequestedAt: serverTimestamp()` and
     `expiresAt: deletionRequestedAt + 30 days` onto the profile doc.
   - Cascades `expiresAt` (the same account-wide date, not independently
     computed per document) onto every existing document across `events`,
     `alerts`, `incidents`, and `sessions`, via batched writes (Firestore's
     500-ops-per-batch limit means a long-time user's history may need
     several batches — chunk explicitly, don't assume one batch suffices).
   - If the account is a **caregiver**: also `arrayRemove`s their own email
     from any patient's `linkedCaregiverEmails` immediately (reusing the
     existing `findLinkedPatient` lookup) — cheap, not tamper-sensitive in
     the same way, and there is no reason to keep an about-to-be-deleted
     caregiver actively linked for 30 more days. If they cancel within the
     window, re-adding the email is a normal, un-gated part of undoing the
     request (see cancel, below) — no special-casing needed there.
   - The account is **not** signed out. Signing out would make "sign back
     in to cancel" the same action as "sign back in to check if it worked,"
     which is a confusing UX collision. Instead:
4. **A persistent, unmissable "Scheduled for deletion on [date] — Cancel"
   banner** replaces normal Home/navigation for the remainder of the
   session and on every subsequent sign-in, checked via the profile doc's
   `deletionRequestedAt` field as part of the existing `go_router` redirect
   guard (§1.2/§2.2) — the same mechanism that already gates Sign-in vs
   Home, extended with one more state. The rest of the app (Live Call, tap-
   only support, Help now) stays reachable underneath it; a pending
   deletion should never block someone from reaching support in the
   meantime.
5. **Cancel**, at any point before expiry: clears `deletionRequestedAt` and
   `expiresAt` from the profile doc and from every subcollection document
   touched in step 3 (a symmetric cascade, same batching), restoring each
   document's `expiresAt` to its original `createdAt + 180d` general-
   retention value rather than leaving it null (leaving it null would
   silently opt that document out of the M7 general-retention policy
   forever, which isn't what "I changed my mind about deleting my account"
   should mean).
6. **Within ~31 days, unattended:** Firestore TTL deletes the profile doc
   and every subcollection document whose `expiresAt` has passed. No app
   code executes. If the person never opens the app again, the data is
   still gone — which is the entire point of a background TTL mechanism
   over a client-triggered one.

#### 5.6.4 The Firebase Auth record — a named, not hidden, gap

Firestore TTL can erase Firestore *data*. It **cannot** delete the Firebase
Authentication user object itself (uid, email, display name, photo URL —
sourced from Google Sign-In, no app content) — that requires the Admin SDK,
i.e. a Cloud Function, unavailable on Spark. Two options were weighed:

- **Delete the Auth user immediately at request time.** Rejected: it breaks
  "sign back in to cancel" outright, since Firebase treats a subsequent
  Google sign-in as a brand-new uid with no path back to the old, still-
  mid-cooling-period profile document.
- **Leave the Auth record alone through the window (recommended, and what
  the flow above assumes).** Consequence, stated plainly rather than
  solved: if someone never signs in again after their data is erased, an
  empty Auth entry — containing nothing beyond what Google's own sign-in
  already independently holds for them — persists with no automated
  cleanup path on Spark. If they *do* sign in again after expiry, the app
  finds no profile doc and simply routes them to onboarding as a new user —
  which requires no special-case code at all, since "no profile" and "new
  user" are already the same code path.

Manual, periodic Admin-console cleanup of Auth users with no matching
Firestore profile is the only closing move available on Spark; note it as
an occasional operational task, not something to build.

#### 5.6.5 Data export (right to portability)

**Settings → Data & Privacy → "Download everything we have about you."**
Already anticipated in §5.2's original recommendation; specified concretely
here:

- Client-side only, no backend needed: read the profile doc plus every
  document the account can already read under its own ownership per
  `firestore.rules` (i.e., export scope mirrors read-access scope exactly —
  if a rule change ever grants a new readable field, export picks it up
  automatically rather than needing a parallel list maintained by hand).
- Bundle into a single JSON file, human-readable field names, grouped by
  collection. Use `share_plus` (**new dependency**, not yet in
  `pubspec.yaml`) rather than a direct filesystem write — Android's scoped
  storage makes writing straight to Downloads unreliable across OS
  versions; routing through the system share sheet lets the person save,
  email, or send the file wherever they want without the app needing
  storage permissions it otherwise has no reason to hold.
- Available regardless of whether deletion is pending — exporting first,
  then deleting, is exactly the flow GDPR portability exists to support,
  and the two features should visibly sit next to each other in the UI for
  that reason.
- **Caregiver accounts** get the same entry point; their export is just
  smaller (their own profile doc — they own no events/alerts/incidents/
  sessions subcollections of their own).
- **Scope note for `src/` (the web caregiver dashboard):** it currently has
  no Settings/Account area at all. A caregiver is a data subject too and
  has the same Article 17/20 rights over their own profile doc. Out of
  scope to build in this pass — flagged so it isn't forgotten, not silently
  dropped — but the underlying mechanism (rules below, export-scope-mirrors-
  read-scope) is already role-agnostic and reusable there without redesign
  when that work happens.

#### 5.6.6 Security rules — drafted here, not yet deployed

Rules changes are drafted now for review, but **not applied to the live
`firestore.rules` yet** — they have no caller until Settings exists (M7),
and a shared, already-hardened, two-app-consumed rules file should change
alongside the feature that exercises it, with tests, not speculatively.

```
// Extends isValidOwnerProfileUpdate to allow initiating/cancelling deletion,
// in addition to the existing emergencyContact/linkedCaregiverEmails edits.
function isValidDeletionRequest() {
  let before = resource.data;
  let after = request.resource.data;
  return after.diff(before).affectedKeys().hasOnly(['deletionRequestedAt', 'expiresAt']) &&
    isRecentServerTimestamp('deletionRequestedAt') &&
    after.expiresAt == after.deletionRequestedAt + duration.value(30, 'd');
}

function isValidDeletionCancel() {
  let before = resource.data;
  let after = request.resource.data;
  return after.diff(before).affectedKeys().hasOnly(['deletionRequestedAt', 'expiresAt']) &&
    !('deletionRequestedAt' in after) &&
    // Cancelling restores general 180-day retention, it doesn't opt out of
    // TTL entirely — see §5.6.3 step 5.
    ('expiresAt' in after ? after.expiresAt == before.createdAt + duration.value(180, 'd') : true);
}

// New: lets a client set ONLY expiresAt on an otherwise-immutable document,
// and only in lockstep with the account-wide deletion date on its own
// parent profile — never an independently-chosen date. This is what makes
// §5.6.1's distinction (account deletion vs. single-incident deletion)
// real rather than aspirational: without the get() check below, this would
// silently reopen the exact loophole §5.2 closed.
function isValidExpiryCascade(uid) {
  let profile = get(/databases/$(database)/documents/users/$(uid)).data;
  return isOwner(uid) &&
    request.resource.data.diff(resource.data).affectedKeys().hasOnly(['expiresAt']) &&
    (
      // Cascading a deletion request: must match the profile's own schedule exactly.
      ('deletionRequestedAt' in profile && request.resource.data.expiresAt == profile.expiresAt) ||
      // Cascading a cancellation: back to this specific document's own general retention.
      (!('deletionRequestedAt' in profile) &&
       request.resource.data.expiresAt == resource.data.createdAt + duration.value(180, 'd'))
    );
}
```

Applied as `allow update: if isValidEvent-style-create... || isValidExpiryCascade(uid);`
alongside the existing `allow create` on each of `events`, `alerts`,
`incidents`, and `sessions` — `allow delete` stays `false` everywhere,
unchanged; TTL never needs it, per §5.6.2.

---

## 6. Efficiency

- **Battery/thermal budget**: rough estimate, to be measured not trusted —
  continuous mic capture + socket + playback alone: low single-digit %/hour.
  Add continuous camera streaming (even motion-gated): meaningfully more,
  plausibly 10–15%/hour combined depending on device and screen brightness.
  Keep the call screen's own brightness modest (don't force max brightness;
  respect system auto-brightness) since the screen itself is a real
  contributor at that duration. The thermal guardrail in §4.3 is the safety
  valve if this runs hot on a given device.
- **Network usage**: 16kHz×16-bit mono outbound ≈ 256kbps raw, ×~1.33 for
  base64 ≈ ~340kbps sustained outbound during active speech. 24kHz×16-bit
  mono inbound ≈ 384kbps raw, similarly inflated by base64 ≈ ~510kbps
  sustained inbound during model speech. Add camera frames (~15–30KB every
  1.5–2s when the scene is moving) on top. Combined, a camera-on
  conversation is roughly **0.5–1 Mbps sustained**, which is real data usage
  on a cellular plan — worth an explicit heads-up (§1.6: weak-connection and
  cellular-data copy) rather than a silent surprise on someone's bill.
- **Memory**: the playback ring buffer and mic-frame batching buffers must
  be bounded and reused, not allocated fresh per chunk/frame — a naive
  per-frame `Uint8List` allocation over a 20–30 minute call is a meaningful
  amount of garbage-collector churn; pool/reuse buffers in the platform
  channel and in the Dart-side framer.
- **Poor connectivity**: use `connectivity_plus` (already added) to detect
  a metered/cellular or weak connection **before** offering to start a
  call (§1.6 copy), and mid-call, treat repeated reconnect failures (§7.2)
  as a signal to proactively suggest the tap-only fallback rather than let
  the person keep hitting a wall silently.
- **Backgrounding/screen-lock**: covered in depth in §3.9. Camera pauses,
  mic+socket persist via the foreground service, with the model told
  explicitly via a director note the moment the camera goes dark so it
  doesn't confusingly keep referencing a view it no longer has.

---

## 7. Offline & connectivity

### 7.1 What works with no network

- **Tap-only support**: deliberately designed as a fully offline-capable
  path, not merely "works if the network happens to be up." Its scenario
  scripts are bundled locally as static assets, not fetched — a person with
  zero signal still has something. This is the offline story for the app as
  a whole, and it should be positioned as a real, dignified fallback in
  copy, not an apologetic degraded mode (§1.6 phrasing: "That one works
  offline," stated as a plain fact, not an excuse).
- **Emergency dialer** (`tel:` via `url_launcher`, already added): works
  with zero data connection — it's a native phone call, not an app feature
  routed through the internet.
- **Queued Firestore writes**: `cloud_firestore`'s SDK-level offline
  persistence automatically queues writes (check-ins, events) made while
  offline and syncs them once connectivity returns — this is free
  correctness from the SDK, worth relying on rather than re-implementing,
  and worth explicitly testing (write a check-in in airplane mode, confirm
  it appears once reconnected).
- **What does not work offline**: the live voice/vision conversation itself
  — it's inherently a realtime API call. Be honest about this in the UI
  rather than letting someone tap "Start talking" into a silent failure.

### 7.2 Reconnection strategy mid-session

A dropped socket mid-conversation must never leave a UI that still claims
"LIVE" while nothing is actually connected — that's the specific failure
mode most likely to feel like betrayal to someone relying on this in a
crisis. Concretely:

- On socket close/error mid-call: attempt reconnection with backoff (e.g.
  1s, 3s, 8s — 3 attempts), during which the UI shows the "We got
  disconnected for a second — trying to get back to you…" state (§1.6), not
  a frozen "LIVE" badge.
- On successful reconnect: send a short director-note-style message
  (matching the pattern already used for camera-state and continuity
  briefings) so the model's next utterance acknowledges the gap naturally
  ("sorry, dropped for a second there") rather than resuming as if nothing
  happened — small, but it's the difference between the app feeling aware
  of what just happened to the person and not.
- On exhausting retries: transition to the explicit "line dropped" state
  with both a retry action and a direct path to tap-only support — never a
  dead end with no next step.
- Preserve the local transcript across a reconnect; don't wipe visible
  history just because the underlying session object was replaced.

### 7.3 Queued writes

Incident writes (which can carry an embedded base64 photo up to the
`firestore.rules`-enforced 400KB cap) queue and sync like any other
Firestore write while offline — no special handling needed beyond what the
SDK already provides, though it's worth confirming in testing that a queued
incident write with an embedded photo doesn't get silently dropped or
truncated by the SDK's offline write-size handling before it reaches the
server (test explicitly, don't assume).

---

## 8. Phased delivery plan

Each milestone is independently shippable/demoable and has a concrete
definition of done — not just "feature complete."

**M0 — Auth & profile shell.** Google sign-in, profile-doc creation matching
`firestore.rules`' schema exactly, emergency contact + caregiver-linking
Settings UI, navigation shell with `go_router`. *DoD*: a real account can
sign in, set an emergency contact, nominate a caregiver by email, and the
resulting Firestore document is byte-for-byte compatible with what the web
dashboard already reads — verified by opening the same account in the web
dashboard and confirming it renders.

**M1 — Tap-only fallback flow.** No mic/camera involved. Scenario buttons →
canned grounding scripts, logs `events` to Firestore, emergency dialer
button, fully offline-capable. *DoD*: airplane-mode test passes end to end;
ships real value standing alone, independent of the audio pipeline being
finished.

**M2 — Audio pipeline spike.** Isolated proof-of-concept screen (not the
real Live Call UI yet): mic → 16kHz PCM → `startMediaStream`, and 24kHz
playback via the `AudioTrack` platform channel, holding a basic two-way
voice exchange with the model. *DoD*: a real back-and-forth conversation
works; barge-in flush is demonstrably clean (no audible pop/click);
round-trip latency measured with a stopwatch against the §3.6 budget;
resolves the `startMediaStream` payload-shape and `realtimeInputConfig`
exposure open questions from §3.2/§3.5 concretely, in code, not in this
document.

**M3 — Full live call screen.** Wire the real Live Call UI (§1.3) to the
proven pipeline from M2, plus the ported system instruction, VAD config,
and continuity briefing (`sessionMemory.ts` equivalent). *DoD*: voice-only
(no camera) conversations are behaviorally comparable to the web app for
the same scripted test inputs — verified by a side-by-side scripted session
against both apps.

**M4 — Camera integration.** Motion-gated frame streaming (§4.1), camera
toggle with director notes, thermal guardrail (§4.3). *DoD*: visual
grounding coaching works end to end; a 15-minute synthetic on-device test
with camera+mic+network active does not trigger `THERMAL_STATUS_SEVERE` on
a representative mid-range device, or if it does, the graceful-degrade path
is confirmed working rather than the app crashing/being killed.

**M5 — Safety tool integration.** `flagRelapseRisk` handling, evidence
snapshot capture, incident banner (including the non-dismissible escalated
variant with haptic), caregiver alert write. *DoD*: matches the web's
escalation semantics exactly against a scripted test session; the caregiver
dashboard (`src/`) picks up the resulting `incidents`/`alerts` documents in
real time, unmodified — proving the shared-backend contract holds.

**M6 — Background resilience.** Foreground service, audio focus handling,
headset routing (output), reconnection logic (§7.2). *DoD*: a call survives
5 minutes of screen lock; survives an incoming phone call interruption and
either resumes or degrades gracefully per §3.7; survives headphone unplug
without blasting the speaker; tested on a real device matrix of at least 2–3
physical Android phones (not emulator-only) spanning at least one Android
14+ device.

**M7 — Security & privacy hardening.** `FLAG_SECURE` on the two flagged
screens, Firebase App Check + Play Integrity registration, `local_auth`
biometric gate defaulting on after first caregiver link, Firestore TTL
policies on `incidents`/`sessions`/`events`/`users` with `expiresAt`
written at creation time (§5.2), consent copy from §5.1 built and reviewed,
**account deletion and data export (§5.6) built end to end**: Settings UI,
the drafted rules changes deployed alongside it (not before), the batched
cascade-write and cancel paths, and the `share_plus` export flow. *DoD*:
every item in §5.5's "ethically thin" list has either been resolved or has
an explicit, documented, deliberate decision not to resolve it for v1 —
silence is not an acceptable outcome for that list; a scripted test account
can request deletion, cancel it, request it again, and be confirmed (via
direct Firestore inspection, since ~31-day TTL isn't practical to wait out
in CI) to have `expiresAt` correctly cascaded across every one of its own
documents and nowhere it shouldn't be.

**M8 — Accessibility & polish.** TalkBack audit of the full crisis flow,
reduced-motion verification, golden tests across text-scale/theme/TalkBack
matrix (§2.5), empty/error/offline copy pass (§1.6). *DoD*: a full TalkBack
walkthrough of the Live Call screen, performed by someone not looking at the
screen, succeeds in starting a call, toggling the camera, and ending the
call.

**M9 — Release prep.** Crashlytics, Play Store listing, staged rollout plan.
*DoD*: standard release checklist; not detailed further here as it's outside
the design scope of this document.

### Deliberately cut from v1

- **History / past-sessions browsing screen.** `sessionMemory.ts`'s
  continuity briefing (referencing the last session in conversation) is kept
  — that's cheap and high-value — but a UI for browsing/searching past
  sessions is cut; it's not core to the crisis-support job and adds a real
  surface for the offline-cache/FLAG_SECURE concerns in §5.3 to spread into.
- **Bluetooth mic input (SCO).** Output-only Bluetooth ships; mic-over-BT is
  cut per §3.8 — narrowband quality and fragile/hard-to-CI-test routing
  aren't worth the risk to the core call experience in v1.
- **Material You dynamic color.** The fixed ember palette is the v1 default
  and, per §1.1's argument, may simply be the permanent decision rather than
  a temporary v1 cut — but if user research says otherwise, an opt-in dynamic
  mode is the kind of thing to add later, not to build speculatively now.
- **Multi-locale/multi-region helplines.** India-only for v1, matching the
  web app's current scope and its own explicit code comment — do not expand
  to other regions without re-verifying real, current crisis-line numbers
  for each one; a stale number is actively dangerous, not just incomplete.
- **Caregiver-initiated push notifications / any Cloud-Functions-dependent
  feature.** Out of scope while on the Spark plan by hard constraint, not a
  choice being made here.
- **Patient-initiated incident deletion.** Decided against, not deferred
  (§5.2) — incidents stay fully immutable. Only the TTL-policy half ships,
  in M7.

---

## 9. Risks, ranked, with mitigations

1. **Barge-in / playback-flush doesn't actually work cleanly.** The model
   talks over the user, or playback glitches/pops during flush — happening
   during a crisis conversation, this is the single most likely thing to
   make the app feel *broken* at the worst possible moment. *Mitigation*:
   M2 is a dedicated spike specifically to prove this out before any other
   UI is built on top of it; extensive real-device testing, not emulator-only.

2. **Foreground service / Android 14+ restrictions silently kill the call on
   screen lock.** Someone mid-crisis loses the line with no warning.
   *Mitigation*: M6 explicitly tests screen-lock survival on a real Android
   14+ device; the reconnection/"line dropped" UI (§7.2) is the safety net
   if the service approach has gaps on some OEM skin.

3. **Echo cancellation fails on some device/OEM combination**, producing an
   echo loop or the model responding to its own voice. *Mitigation*: the
   `voiceCommunication` source / `AudioAttributes` pairing plus explicit
   `AcousticEchoCanceler` check (§3.4), with a defined mute-during-playback
   fallback rather than an undefined failure; tested across the device
   matrix in M6, not assumed from one test phone.

4. **No deletion path for relapse evidence, by decision (§5.2).** A patient
   who asks "can you delete that photo of me" will get "no" — that answer is
   now deliberate, not an oversight, but it's still a real trust cost that
   the consent copy in §5.1 must not undersell. *Mitigation*: the §5.1
   consent script already says "even if you don't want it to right then" —
   keep that phrasing intact through implementation; it's doing the work of
   setting this expectation honestly, in advance, rather than the app
   discovering the limitation in the moment someone asks. TTL policy (M7)
   remains the only retention control.

5. **Self-harm/suicide cues handled only by model judgment, no deterministic
   backstop.** A missed cue here is categorically worse than most other
   failure modes in the app. *Mitigation*: the client-side keyword backstop
   in §5.4, shipped by M5 alongside the other safety-tool work, not treated
   as a nice-to-have.

6. **"Caregiver has been notified" reads as a guarantee it isn't.** With no
   server push (hard constraint), an escalation only reaches a caregiver
   whose dashboard happens to be open — the current banner copy ("Your
   caregiver has been notified") could reasonably be misread as "someone
   will act on this," which may not be true. *Mitigation*: tighten the copy
   to be honest about this specifically (e.g. "...and your caregiver will
   see this next time they open their dashboard"), and treat any future
   SMS/push-based caregiver notification as a Blaze-plan-dependent v2
   feature, not something to imply exists today.

7. **Thermal/battery throttling degrades call quality mid-session with no
   warning to the user.** *Mitigation*: the `PowerManager` thermal listener
   and graceful audio-only degrade in §4.3/§4.4, tested explicitly in M4.

8. **Cellular data usage surprises someone on a capped plan** mid-crisis,
   potentially the worst moment for their phone to also become unusable for
   other things. *Mitigation*: proactive weak-connection/data-usage copy in
   §1.6, before the call starts wherever detectable.

9. **Motion-gating constants tuned for the web's canvas-based diff don't
   transfer 1:1 to the YUV-plane approach on mobile**, risking either
   excess battery draw (threshold too sensitive) or stale vision coaching
   (threshold too loose). *Mitigation*: explicitly re-benchmarked on-device
   in M4 rather than copy-pasted, per §4.2.

10. **Bluetooth mic routing is flaky and hard to test reliably.**
    *Mitigation*: cut from v1 entirely (§3.8, §8) rather than shipped in an
    unreliable state — the highest-leverage mitigation for this one is
    simply not building it yet.

11. **The account-deletion cascade (§5.6.3) partially fails mid-batch** —
    network drops after some documents have `expiresAt` rewritten to the
    deletion date and others don't, leaving an account half-scheduled: some
    data erased on time, some silently retained past when the person was
    told everything would be gone. *Mitigation*: design the cascade to be
    **idempotent and safely resumable** rather than one-shot — each batch
    only needs to touch documents whose `expiresAt` doesn't already match
    the target date, so re-running the same cascade after a partial failure
    (on next app open, or via a retry button on the pending-deletion banner
    itself) is cheap and correct without special-casing "resume." Verify
    this specific resume behavior in M7's test pass, not just the happy path.
