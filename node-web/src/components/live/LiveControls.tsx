import { MicIcon, CameraIcon, EndCallIcon, MenuIcon } from '../icons'
import HelpNowSheet from '../HelpNowSheet'
import type { CameraAvailability } from '../../lib/cameraAvailability'
import type { EmergencyContact } from '../../lib/emergencyContacts'

const focusRing =
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ember focus-visible:ring-offset-2 focus-visible:ring-offset-void'

interface LiveControlsProps {
  live: boolean
  connecting: boolean
  cameraOn: boolean
  camera: CameraAvailability
  emergencyContact: EmergencyContact | null
  onStart: () => void
  onToggleCamera: () => void
  onEndCall: () => void
  onOpenFallback: () => void
}

/** The bottom control pill (in-call) / start button (idle) row. */
export default function LiveControls({
  live,
  connecting,
  cameraOn,
  camera,
  emergencyContact,
  onStart,
  onToggleCamera,
  onEndCall,
  onOpenFallback,
}: LiveControlsProps) {
  if (!live) {
    return (
      <div className="flex w-full max-w-sm flex-col items-center gap-4">
        <button
          type="button"
          onClick={onStart}
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
    )
  }

  return (
    <div className="flex items-center gap-5 rounded-full border border-line/60 bg-card/70 px-5 py-3 shadow-[0_10px_40px_-10px_rgba(0,0,0,0.7)] backdrop-blur-xl">
      <button
        type="button"
        onClick={onToggleCamera}
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
        onClick={onEndCall}
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
  )
}
