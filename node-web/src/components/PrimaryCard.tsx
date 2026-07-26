interface Props {
  loading: boolean
  error: string | null
  script: string | null
  onSpeakAgain: () => void
}

export default function PrimaryCard({ loading, error, script, onSpeakAgain }: Props) {
  return (
    <div
      className="min-h-44 w-full rounded-2xl border border-line bg-card p-6 text-left shadow-[0_1px_0_rgba(255,255,255,0.03)_inset]"
      role="log"
      aria-live="polite"
    >
      {loading && (
        <div className="flex items-center gap-2 text-sm text-ink-muted">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" aria-hidden="true" />
          Reaching out to your companion…
        </div>
      )}
      {!loading && error && (
        <p className="text-sm text-ink-muted">
          Couldn&apos;t reach the AI companion right now. Please try again.
        </p>
      )}
      {!loading && !error && script && (
        <div className="flex flex-col gap-5">
          <p className="whitespace-pre-wrap font-display text-[19px] leading-relaxed text-ink">
            {script}
          </p>
          <button
            type="button"
            onClick={onSpeakAgain}
            className="min-h-14 self-start rounded-full border border-line px-5 text-sm text-ink-muted transition hover:border-ember/50 hover:text-ink active:scale-95"
          >
            🔊 Speak again
          </button>
        </div>
      )}
      {!loading && !error && !script && (
        <p className="text-sm text-ink-muted">Tap a card below whenever you need it.</p>
      )}
    </div>
  )
}
