import { useState } from 'react'

interface Props {
  /** The exact function the proactive engine calls when it detects elevated stress. */
  onSimulateCrisis: () => void
  /** The exact function the Caregiver Alert button calls. */
  onTestCaregiverSync: () => void
  /** Forces the tap-only fallback, as if mic/voice were unavailable on this device. */
  voiceBlocked: boolean
  onToggleVoiceBlocked: () => void
  busy: boolean
}

/**
 * A discreet panel so an evaluator can exercise every flow on demand instead of
 * waiting for real conditions (frantic tapping, a high-risk-hour silence, a
 * second device).
 *
 * Every control here calls the SAME production function as its organic trigger —
 * real Gemini calls, real Firestore writes. Nothing in this dock produces a
 * canned or simulated response.
 */
export default function EvaluatorDock({
  onSimulateCrisis,
  onTestCaregiverSync,
  voiceBlocked,
  onToggleVoiceBlocked,
  busy,
}: Props) {
  const [open, setOpen] = useState(false)

  return (
    <div className="fixed inset-x-0 bottom-0 z-50">
      {open && (
        <div className="mx-auto max-w-md border-t border-line bg-card px-5 py-4 lg:max-w-2xl">
          <p className="mb-3 text-xs text-ink-muted">
            Each control runs the real code path — live Gemini calls and real database writes,
            the same as the organic trigger.
          </p>
          <div className="flex flex-col gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={onSimulateCrisis}
              className="min-h-14 w-full rounded-xl border border-line px-4 text-left text-sm text-ink transition hover:border-ember/40 disabled:opacity-40"
            >
              Simulate crisis event
              <span className="block text-xs text-ink-muted">
                Fires the proactive engine&apos;s elevated-stress intervention
              </span>
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={onTestCaregiverSync}
              className="min-h-14 w-full rounded-xl border border-line px-4 text-left text-sm text-ink transition hover:border-ember/40 disabled:opacity-40"
            >
              Test caregiver sync
              <span className="block text-xs text-ink-muted">
                Generates a caregiver script and writes it to their live feed
              </span>
            </button>
            <button
              type="button"
              onClick={onToggleVoiceBlocked}
              className="min-h-14 w-full rounded-xl border border-line px-4 text-left text-sm text-ink transition hover:border-ember/40"
            >
              {voiceBlocked ? 'Restore voice mode' : 'Simulate voice unavailable'}
              <span className="block text-xs text-ink-muted">
                {voiceBlocked
                  ? 'Re-enable the live voice channel'
                  : 'Force the tap-only fallback, as on a device with no mic'}
              </span>
            </button>
          </div>
        </div>
      )}
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="w-full bg-void/95 py-2 text-center text-[10px] tracking-[0.2em] text-ink-muted/60 transition hover:text-ink-muted"
      >
        {open ? 'HIDE EVALUATOR TOOLS' : 'EVALUATOR TOOLS'}
      </button>
    </div>
  )
}
