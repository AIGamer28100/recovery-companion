interface Props {
  onReset: () => void
}

export default function EmergencyResetButton({ onReset }: Props) {
  return (
    <button
      type="button"
      onClick={onReset}
      className="min-h-14 w-full rounded-xl border border-gray-700 text-sm font-medium text-gray-200 active:scale-[0.98]"
    >
      One-Tap Emergency Reset
    </button>
  )
}
