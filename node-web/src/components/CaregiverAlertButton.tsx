interface Props {
  disabled: boolean
  onTrigger: () => void
}

export default function CaregiverAlertButton({ disabled, onTrigger }: Props) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onTrigger}
      className="min-h-14 w-full rounded-xl bg-ink text-sm font-semibold text-void transition active:scale-[0.98] disabled:opacity-40"
    >
      Caregiver Alert Script
    </button>
  )
}
