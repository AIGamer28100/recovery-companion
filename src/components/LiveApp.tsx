import { useLiveSession } from '../hooks/useLiveSession'
import ReactiveOrb, { OrbGlowBar } from './live/ReactiveOrb'
import LiveTranscript from './live/LiveTranscript'
import LiveControls from './live/LiveControls'
import type { UserProfile } from '../types'

interface Props {
  uid: string
  profile: UserProfile
  onOpenFallback: () => void
}

export default function LiveApp({ uid, profile, onOpenFallback }: Props) {
  const emergencyContact = profile.emergencyContact ?? null
  const hasLinkedCaregiver = (profile.linkedCaregiverEmails?.length ?? 0) > 0

  const {
    status,
    cameraOn,
    camera,
    errorMsg,
    lines,
    incidentStage,
    videoRef,
    startCall,
    endCall,
    toggleCamera,
    dismissIncident,
  } = useLiveSession({ uid, emergencyContact, hasLinkedCaregiver })

  const live = status === 'live'
  const connecting = status === 'connecting'
  // Purely presentational: how fast the orb breathes/pulses in each state.
  const orbSpeed = live ? '2.2s' : connecting ? '3.4s' : '9s'

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
        <ReactiveOrb orbSpeed={orbSpeed} cameraOn={cameraOn} />

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
                onClick={dismissIncident}
                className="ml-2 underline underline-offset-2 opacity-80 hover:opacity-100"
              >
                Dismiss
              </button>
            </div>
          )}

          {live && cameraOn && <OrbGlowBar orbSpeed={orbSpeed} />}

          {live && <LiveTranscript lines={lines} />}

          <LiveControls
            live={live}
            connecting={connecting}
            cameraOn={cameraOn}
            camera={camera}
            emergencyContact={emergencyContact}
            onStart={startCall}
            onToggleCamera={toggleCamera}
            onEndCall={endCall}
            onOpenFallback={onOpenFallback}
          />
        </div>
      </div>
    </div>
  )
}
