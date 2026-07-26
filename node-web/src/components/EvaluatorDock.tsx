import { useState } from 'react'

interface Props {
  /** The exact function the proactive engine calls when it detects elevated stress. */
  onSimulateCrisis: () => void
  /** The exact function the Caregiver Alert button calls. */
  onTestCaregiverSync: () => void
  /** Returns to the live voice screen — the same navigation as the header link. */
  onOpenVoiceMode: () => void
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
  onOpenVoiceMode,
  busy,
}: Props) {
  const [open, setOpen] = useState(false)

  return (
    <div className="fixed inset-x-0 bottom-0 z-50">
      <div
        id="evaluator-tools-panel"
        hidden={!open}
        className="mx-auto max-w-md border-t border-line bg-card px-5 py-4 lg:max-w-2xl"
      >
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
            onClick={onOpenVoiceMode}
            className="min-h-14 w-full rounded-xl border border-line px-4 text-left text-sm text-ink transition hover:border-ember/40"
          >
            Open live voice mode
            <span className="block text-xs text-ink-muted">
              Switches to the Gemini Live screen — real audio session, camera optional
            </span>
          </button>
        </div>
      </div>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-controls="evaluator-tools-panel"
        className="w-full bg-void/95 py-2 text-center text-[10px] tracking-[0.2em] text-ink-muted/60 transition hover:text-ink-muted"
      >
        {open ? 'HIDE EVALUATOR TOOLS' : 'EVALUATOR TOOLS'}
      </button>
    </div>
  )
}
