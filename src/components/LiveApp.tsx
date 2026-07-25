import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react'
import { startAudioConversation } from 'firebase/ai'
import type { AudioConversationController, LiveSession } from 'firebase/ai'
import { connectLiveSession, VISION_CHECK_PROMPT } from '../lib/geminiLive'
import { teeSession } from '../lib/liveTee'
import { VideoFrameStreamer } from '../lib/videoStream'
import { logEvent, logCaregiverAlert } from '../lib/events'
import { recordRelapseIncident } from '../lib/incidents'
import { buildContinuityBriefing, saveSessionTranscript } from '../lib/sessionMemory'
import {
  detectCameraAvailability,
  describeCameraForModel,
  type CameraAvailability,
} from '../lib/cameraAvailability'
import type { RelapseStage } from '../lib/safetyTools'
import type { UserProfile } from '../types'
import { describeSupportForModel } from '../lib/emergencyContacts'
import HelpNowSheet from './HelpNowSheet'

type Status = 'idle' | 'connecting' | 'live' | 'error'

/** How often the vision coach considers nudging. */
const COACH_TICK_MS = 5000
/**
 * Both sides must have been quiet this long before a nudge is even considered.
 * Generous on purpose: someone going quiet is usually mid-exercise or thinking,
 * and a companion that pipes up every few seconds is worse than one that waits.
 */
const QUIET_BEFORE_NUDGE_MS = 25000
/** Hard floor between nudges, so a long silence can't turn into a drip of prompts. */
const MIN_NUDGE_GAP_MS = 60000

interface TranscriptLine {
  role: 'you' | 'companion'
  text: string
}

interface Props {
  uid: string
  profile: UserProfile
  onOpenFallback: () => void
}

/* Presentational icon glyphs — inline SVG, no external assets. */
function MicIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path
        d="M12 15a3 3 0 0 0 3-3V6a3 3 0 1 0-6 0v6a3 3 0 0 0 3 3Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M19 11a7 7 0 0 1-14 0M12 18v3"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function CameraIcon({ className, off }: { className?: string; off?: boolean }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <rect x="3" y="6" width="13" height="12" rx="2.5" stroke="currentColor" strokeWidth="1.6" />
      <path d="m16 10.5 5-2.8v8.6l-5-2.8" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      {off && <path d="M3 3l18 18" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />}
    </svg>
  )
}

function EndCallIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path d="M6 6l12 12M18 6 6 18" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
    </svg>
  )
}

function MenuIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden="true">
      <circle cx="5" cy="12" r="1.7" />
      <circle cx="12" cy="12" r="1.7" />
      <circle cx="19" cy="12" r="1.7" />
    </svg>
  )
}

export default function LiveApp({ uid, profile, onOpenFallback }: Props) {
  const emergencyContact = profile.emergencyContact ?? null
  const hasLinkedCaregiver = (profile.linkedCaregiverUids?.length ?? 0) > 0
  const [status, setStatus] = useState<Status>('idle')
  const [cameraOn, setCameraOn] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [lines, setLines] = useState<TranscriptLine[]>([])
  const [incidentStage, setIncidentStage] = useState<RelapseStage | null>(null)
  const [camera, setCamera] = useState<CameraAvailability>({
    state: 'unsupported',
    canOffer: false,
  })
  const transcriptEndRef = useRef<HTMLDivElement | null>(null)

  const sessionRef = useRef<LiveSession | null>(null)
  const controllerRef = useRef<AudioConversationController | null>(null)
  const streamerRef = useRef<VideoFrameStreamer | null>(null)
  const cameraStreamRef = useRef<MediaStream | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)

  const lastActivityRef = useRef<number>(0)
  const lastNudgeRef = useRef<number>(0)
  const coachTimerRef = useRef<number | null>(null)
  const cameraOnRef = useRef(false)

  const stopVisionCoach = useCallback(() => {
    if (coachTimerRef.current !== null) {
      window.clearInterval(coachTimerRef.current)
      coachTimerRef.current = null
    }
  }, [])

  /**
   * Nudges the model to re-check the camera, but only during a genuine lull —
   * never while either side is mid-sentence. Without the silence gate this
   * becomes a companion that talks over you every few seconds.
   */
  const startVisionCoach = useCallback(() => {
    stopVisionCoach()
    coachTimerRef.current = window.setInterval(() => {
      const session = sessionRef.current
      if (!session || session.isClosed || !cameraOnRef.current) return

      const now = Date.now()
      const quietFor = now - lastActivityRef.current
      const sinceNudge = now - lastNudgeRef.current
      if (quietFor < QUIET_BEFORE_NUDGE_MS || sinceNudge < MIN_NUDGE_GAP_MS) return

      lastNudgeRef.current = now
      void session.sendTextRealtime(VISION_CHECK_PROMPT).catch(() => {
        /* session closing — nothing to do */
      })
    }, COACH_TICK_MS)
  }, [stopVisionCoach])

  const stopCamera = useCallback(() => {
    streamerRef.current?.stop()
    streamerRef.current = null
    cameraStreamRef.current?.getTracks().forEach((t) => t.stop())
    cameraStreamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    cameraOnRef.current = false
    setCameraOn(false)
  }, [])

  const linesRef = useRef<TranscriptLine[]>([])
  linesRef.current = lines

  const endCall = useCallback(async () => {
    stopVisionCoach()
    stopCamera()
    // Persist the conversation so the next session can pick up where this left off.
    const transcript = linesRef.current
      .map((l) => `${l.role === 'you' ? 'Them' : 'You'}: ${l.text}`)
      .join('\n')
    void saveSessionTranscript(uid, transcript).catch((err) =>
      console.warn('Could not save session transcript', err),
    )
    try {
      await controllerRef.current?.stop()
      await sessionRef.current?.close()
    } catch {
      // already torn down
    }
    controllerRef.current = null
    sessionRef.current = null
    setStatus('idle')
  }, [stopCamera, stopVisionCoach, uid])

  // Never leave the mic or camera running if this unmounts.
  useEffect(() => {
    return () => {
      void endCall()
    }
  }, [endCall])

  useEffect(() => {
    transcriptEndRef.current?.scrollIntoView({ block: 'end' })
  }, [lines])

  // Probe for a usable camera up front (without triggering a permission prompt)
  // so the companion never offers something this device can't do. Re-checked when
  // the permission changes, e.g. the user unblocks it mid-call.
  useEffect(() => {
    let cancelled = false
    const refresh = () => {
      void detectCameraAvailability().then((result) => {
        if (!cancelled) setCamera(result)
      })
    }
    refresh()

    let permStatus: PermissionStatus | undefined
    void navigator.permissions
      ?.query({ name: 'camera' as PermissionName })
      .then((status) => {
        permStatus = status
        status.addEventListener('change', refresh)
      })
      .catch(() => {
        /* Permissions API doesn't support 'camera' here — the initial probe stands. */
      })

    navigator.mediaDevices?.addEventListener?.('devicechange', refresh)
    return () => {
      cancelled = true
      permStatus?.removeEventListener('change', refresh)
      navigator.mediaDevices?.removeEventListener?.('devicechange', refresh)
    }
  }, [])

  // Transcripts arrive as small fragments ("How a", "re yo", "u today?"), so
  // consecutive chunks from the same speaker are merged into one line.
  const appendTranscript = useCallback((role: TranscriptLine['role'], chunk: string) => {
    setLines((prev) => {
      const last = prev[prev.length - 1]
      if (last?.role === role) {
        return [...prev.slice(0, -1), { role, text: last.text + chunk }]
      }
      return [...prev.slice(-40), { role, text: chunk }]
    })
  }, [])

  const startCall = async () => {
    setStatus('connecting')
    setErrorMsg(null)
    setLines([])
    try {
      const session = await connectLiveSession()
      sessionRef.current = session

      // startAudioConversation claims the session's single receive() consumer,
      // so tee the stream: audio still flows to playback untouched, and we get
      // a copy of every message for the live transcript.
      const teed = teeSession(session, (message) => {
        if (message.type !== 'serverContent') return
        if (message.inputTranscription?.text) {
          lastActivityRef.current = Date.now()
          appendTranscript('you', message.inputTranscription.text)
        }
        if (message.outputTranscription?.text) {
          lastActivityRef.current = Date.now()
          appendTranscript('companion', message.outputTranscription.text)
        }
      })

      controllerRef.current = await startAudioConversation(teed, {
        functionCallingHandler: async (functionCalls) => {
          const call = functionCalls[0]
          if (call?.name !== 'flagRelapseRisk') {
            return { name: call?.name ?? 'unknown', response: { ok: false } }
          }
          const args = call.args as { stage?: RelapseStage; observation?: string }
          const stage = args.stage === 'escalated' ? 'escalated' : 'intervening'
          try {
            await recordRelapseIncident(uid, stage, args.observation ?? '', videoRef.current)
            if (stage === 'escalated') {
              await logCaregiverAlert(uid, {
                script: `Urgent: ${args.observation ?? 'possible substance use observed on camera'}`,
                triggeredBy: 'relapse_risk',
              })
            }
            setIncidentStage(stage)
            return {
              name: call.name,
              response: {
                ok: true,
                stage,
                caregiverNotified: stage === 'escalated',
              },
            }
          } catch (err) {
            console.error('Failed to record relapse incident', err)
            return { name: call.name, response: { ok: false } }
          }
        },
      })

      lastActivityRef.current = Date.now()
      startVisionCoach()

      // Opens every call as a continuation: the companion greets them, knows the
      // time of day, and remembers the last conversation.
      // Re-probe at call time rather than trusting mount-time state — they may
      // have plugged in a webcam or changed the permission since.
      const cameraNow = await detectCameraAvailability()
      setCamera(cameraNow)

      const briefing = await buildContinuityBriefing(uid)
      void session
        .sendTextRealtime(
          `${briefing}\n\n[Camera: ${describeCameraForModel(cameraNow, false)}]` +
            `\n\n[Support available to them: ${describeSupportForModel(
              emergencyContact,
              hasLinkedCaregiver,
            )}]`,
        )
        .catch(() => {})

      setStatus('live')
      logEvent(uid, { type: 'live_conversation', mood: null })
    } catch (err) {
      console.error('Live conversation failed to start', err)
      setErrorMsg(
        err instanceof DOMException
          ? 'Microphone access is blocked. Allow it in your browser and try again.'
          : "Couldn't open the line. Check your connection and try again.",
      )
      setStatus('error')
      await endCall()
      setStatus('error')
    }
  }

  const toggleCamera = async () => {
    if (cameraOn) {
      stopCamera()
      void sessionRef.current
        ?.sendTextRealtime(
          `[Silent director note, not from the user. Their camera is now OFF — you can no longer ` +
            `see them. Do not comment on it. Keep coaching by voice alone. ${describeCameraForModel(camera, false)}]`,
        )
        .catch(() => {})
      return
    }
    const session = sessionRef.current
    if (!session) return
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 1280 } },
      })
      cameraStreamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }
      const streamer = new VideoFrameStreamer(session, videoRef.current!)
      streamer.start()
      streamerRef.current = streamer
      cameraOnRef.current = true
      // Give the model a moment of real video before the first nudge.
      lastNudgeRef.current = Date.now()
      setCameraOn(true)
      // Let the model know it can see now, so it can coach visually and stop
      // asking for the camera.
      void session
        .sendTextRealtime(
          `[Silent director note, not from the user. ${describeCameraForModel(camera, true)} ` +
            'Do not announce this or thank them; just start using it. Say nothing right now unless ' +
            'you were mid-exercise with them.]',
        )
        .catch(() => {})
    } catch (err) {
      console.error('Camera unavailable', err)
      setErrorMsg('Camera access is blocked, but the conversation is still going.')
      stopCamera()
    }
  }

  const live = status === 'live'
  const connecting = status === 'connecting'
  // Purely presentational: how fast the orb breathes/pulses in each state.
  const orbSpeed = live ? '2.2s' : connecting ? '3.4s' : '9s'
  const focusRing =
    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-void'

  return (
    <div className="relative flex min-h-[100dvh] flex-col overflow-hidden bg-void text-ink">
      <div className="ember-field" />

      {/* Camera preview fills the screen when on; mirrored like a selfie view. */}
      <video
        ref={videoRef}
        playsInline
        muted
        className={`absolute inset-0 h-full w-full scale-x-[-1] object-cover transition-opacity duration-700 ${
          cameraOn ? 'opacity-60' : 'opacity-0'
        }`}
        aria-hidden="true"
      />

      {/* Scrims keep text and controls legible over a live camera feed. */}
      {cameraOn && (
        <>
          <div
            className="pointer-events-none absolute inset-x-0 top-0 z-[1] h-48 bg-gradient-to-b from-void/95 via-void/50 to-transparent"
            aria-hidden="true"
          />
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 z-[1] h-72 bg-gradient-to-t from-void via-void/70 to-transparent"
            aria-hidden="true"
          />
        </>
      )}

      <div className="relative z-10 flex flex-1 flex-col items-center px-6 pb-6 pt-12 text-center">
        {/* Header */}
        <div className="flex flex-col items-center gap-3">
          <h1 className="font-display text-2xl font-medium sm:text-3xl">Recovery Companion</h1>
          <p className="max-w-xs text-sm leading-relaxed text-ink-muted">
            {status === 'idle' && 'Tap to start talking. No typing, no forms — just talk.'}
            {connecting && 'Opening the line…'}
            {live && cameraOn && 'I can see your space — I’ll use what’s around you to ground you.'}
            {live && !cameraOn && 'I’m listening. Cut in any time.'}
            {status === 'error' && (errorMsg ?? 'Something went wrong.')}
          </p>
          {live && (
            <span className="flex items-center gap-2 text-[11px] font-semibold tracking-[0.25em] text-ember">
              <span className="h-1.5 w-1.5 rounded-full bg-ember motion-safe:animate-pulse" aria-hidden="true" />
              LIVE
            </span>
          )}
        </div>

        {/* The reactive orb: idle and slow at rest, alive during a call. It
            collapses to a bottom glow bar once the camera is on, so it never
            sits on top of the thing the user is trying to show. */}
        <div
          className={`flex flex-1 items-center justify-center py-6 transition-opacity duration-500 ${
            cameraOn ? 'pointer-events-none opacity-0' : 'opacity-100'
          }`}
          aria-hidden={cameraOn}
        >
          <div
            className="relative flex h-48 w-48 items-center justify-center sm:h-56 sm:w-56"
            style={{ '--orb-speed': orbSpeed } as CSSProperties}
          >
            <div
              className="orb-glow absolute -inset-6 rounded-full blur-3xl"
              style={{
                background: 'radial-gradient(circle, var(--color-ember) 0%, transparent 70%)',
                opacity: 0.4,
              }}
              aria-hidden="true"
            />
            <div
              className="orb-ring absolute inset-0 rounded-full border border-ember/40"
              style={{ animationDelay: '0s' }}
              aria-hidden="true"
            />
            <div
              className="orb-ring absolute inset-0 rounded-full border border-ember/25"
              style={{ animationDelay: 'calc(var(--orb-speed) / 3)' }}
              aria-hidden="true"
            />
            <div
              className="orb-ring absolute inset-0 rounded-full border border-ember/15"
              style={{ animationDelay: 'calc(var(--orb-speed) / 3 * 2)' }}
              aria-hidden="true"
            />
            <div
              className="orb-sheen absolute h-32 w-32 rounded-full opacity-50 sm:h-36 sm:w-36"
              style={{
                background: 'conic-gradient(from 0deg, transparent 0%, var(--color-ember) 20%, transparent 40%)',
                animationDuration: 'calc(var(--orb-speed) * 3)',
              }}
              aria-hidden="true"
            />
            <div
              className="orb-core relative h-32 w-32 rounded-full sm:h-36 sm:w-36"
              style={{
                background: 'radial-gradient(circle at 35% 28%, #f3d5a3 0%, var(--color-ember) 55%, #8f5f2a 100%)',
                boxShadow: '0 0 70px 8px var(--color-ember-soft), inset 0 0 30px rgba(0,0,0,0.25)',
              }}
              aria-hidden="true"
            />
          </div>
        </div>

        {/* Bottom stack: glow bar (camera mode), transcript, then controls. */}
        <div className="flex w-full flex-col items-center gap-5">
          {/* Always visible when it happens — the person must know a snapshot was
              taken and whether their caregiver was told. Never silent. */}
          {incidentStage && (
            <div
              className={`w-full max-w-md rounded-2xl border px-4 py-3 text-left text-sm ${
                incidentStage === 'escalated'
                  ? 'border-red-500/50 bg-red-500/10 text-red-200'
                  : 'border-ember/50 bg-ember-soft text-ink'
              }`}
              role="status"
              aria-live="assertive"
            >
              {incidentStage === 'escalated' ? (
                <>
                  <strong className="font-semibold">Your caregiver has been notified.</strong>{' '}
                  A snapshot and note were saved to your record.
                </>
              ) : (
                <>
                  <strong className="font-semibold">Snapshot saved to your record.</strong>{' '}
                  Nobody else has been contacted.
                </>
              )}
              <button
                type="button"
                onClick={() => setIncidentStage(null)}
                className="ml-2 underline underline-offset-2 opacity-80 hover:opacity-100"
              >
                Dismiss
              </button>
            </div>
          )}

          {/* With the camera on, the orb becomes an ambient strip of light so the
              companion still feels present without covering the view. */}
          {live && cameraOn && (
            <div
              className="flex h-8 w-full max-w-md items-end justify-center"
              style={{ '--orb-speed': orbSpeed } as CSSProperties}
              aria-hidden="true"
            >
              <div
                className="orb-glow h-1.5 w-48 rounded-full blur-[6px]"
                style={{
                  background:
                    'linear-gradient(90deg, transparent 0%, var(--color-ember) 50%, transparent 100%)',
                }}
              />
            </div>
          )}

          {live && (
            <div
              className="w-full max-w-md animate-[caption-fade-in_0.3s_ease-out] rounded-3xl bg-void/40 px-4 py-3 text-left backdrop-blur-md motion-reduce:animate-none"
              role="log"
              aria-live="polite"
              aria-label="Live transcript"
            >
              <div className="max-h-40 overflow-y-auto">
                {lines.length === 0 ? (
                  <p className="text-sm text-ink-muted/80">
                    Your words and mine will show up here as we talk.
                  </p>
                ) : (
                  <div className="flex flex-col gap-2.5">
                    {lines.map((line, i) => (
                      <p key={i} className="text-sm leading-relaxed">
                        <span
                          className={`mr-2 text-[10px] font-semibold tracking-[0.15em] ${
                            line.role === 'you' ? 'text-ink-muted' : 'text-ember'
                          }`}
                        >
                          {line.role === 'you' ? 'YOU' : 'COMPANION'}
                        </span>
                        <span className={line.role === 'you' ? 'text-ink-muted' : 'font-medium text-ink'}>
                          {line.text}
                        </span>
                      </p>
                    ))}
                    <div ref={transcriptEndRef} />
                  </div>
                )}
              </div>
            </div>
          )}

          {!live ? (
            <div className="flex w-full max-w-sm flex-col items-center gap-4">
              <button
                type="button"
                onClick={startCall}
                disabled={connecting}
                className={`flex min-h-14 w-full items-center justify-center gap-3 rounded-full bg-ink px-10 text-base font-semibold text-void shadow-[0_8px_30px_-6px_rgba(0,0,0,0.6)] transition active:scale-95 disabled:opacity-50 ${focusRing}`}
              >
                <MicIcon className="h-5 w-5" />
                {connecting ? 'Connecting…' : 'Start talking'}
              </button>
              <HelpNowSheet contact={emergencyContact} />
              <button
                type="button"
                onClick={onOpenFallback}
                className={`min-h-14 text-xs tracking-wide text-ink-muted underline-offset-4 transition hover:text-ink hover:underline ${focusRing} rounded`}
              >
                No mic? Use tap-only support instead
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-5 rounded-full border border-line/60 bg-card/70 px-5 py-3 shadow-[0_10px_40px_-10px_rgba(0,0,0,0.7)] backdrop-blur-xl">
              <button
                type="button"
                onClick={toggleCamera}
                disabled={!cameraOn && !camera.canOffer}
                aria-pressed={cameraOn}
                aria-label={
                  cameraOn
                    ? 'Turn camera off'
                    : camera.state === 'blocked'
                      ? 'Camera blocked in browser settings'
                      : camera.state === 'none'
                        ? 'No camera on this device'
                        : 'Turn camera on'
                }
                title={
                  !cameraOn && camera.state === 'blocked'
                    ? 'Camera is blocked in your browser settings'
                    : !cameraOn && camera.state === 'none'
                      ? 'No camera found on this device'
                      : undefined
                }
                className={`flex h-14 w-14 items-center justify-center rounded-full border transition active:scale-90 disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100 ${focusRing} ${
                  cameraOn ? 'border-ember bg-ember-soft text-ember' : 'border-line/80 bg-void/40 text-ink-muted hover:text-ink'
                }`}
              >
                <CameraIcon className="h-6 w-6" off={!cameraOn} />
              </button>

              <button
                type="button"
                onClick={endCall}
                aria-label="End conversation"
                className={`flex h-16 w-16 items-center justify-center rounded-full bg-red-500 text-white shadow-[0_6px_20px_-4px_rgba(239,68,68,0.7)] transition active:scale-90 ${focusRing}`}
              >
                <EndCallIcon className="h-6 w-6" />
              </button>

              <button
                type="button"
                onClick={onOpenFallback}
                aria-label="Open tap-only support"
                className={`flex h-14 w-14 items-center justify-center rounded-full border border-line/80 bg-void/40 text-ink-muted transition hover:text-ink active:scale-90 ${focusRing}`}
              >
                <MenuIcon className="h-5 w-5" />
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
