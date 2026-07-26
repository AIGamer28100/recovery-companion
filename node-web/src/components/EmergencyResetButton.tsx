interface Props {
  onReset: () => void
}

export default function EmergencyResetButton({ onReset }: Props) {
  return (
    <button
      type="button"
      onClick={onReset}
      className="min-h-14 w-full rounded-xl border border-line text-sm font-medium text-ink-muted transition hover:border-ink-muted/60 hover:text-ink active:scale-[0.98]"
    >
      One-Tap Emergency Reset
    </button>
  )
}
