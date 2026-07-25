interface Props {
  loading: boolean
  error: string | null
  script: string | null
  onSpeakAgain: () => void
}

export default function PrimaryCard({ loading, error, script, onSpeakAgain }: Props) {
  return (
    <div
      className="min-h-40 w-full rounded-2xl border border-gray-800 bg-gray-950 p-6 text-left"
      role="log"
      aria-live="polite"
    >
      {loading && <p className="text-sm text-gray-400">Reaching out to your companion…</p>}
      {!loading && error && (
        <p className="text-sm text-red-400">
          Couldn&apos;t reach the AI companion right now. Please try again.
        </p>
      )}
      {!loading && !error && script && (
        <div className="flex flex-col gap-4">
          <p className="whitespace-pre-wrap text-base leading-relaxed text-white">{script}</p>
          <button
            type="button"
            onClick={onSpeakAgain}
            className="min-h-14 self-start rounded-full border border-gray-700 px-5 text-sm text-gray-200 active:scale-95"
          >
            🔊 Speak again
          </button>
        </div>
      )}
      {!loading && !error && !script && (
        <p className="text-sm text-gray-500">Tap a card below whenever you need it.</p>
      )}
    </div>
  )
}
