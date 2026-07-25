import type { ScenarioKind } from '../types'

const SCENARIOS: { kind: ScenarioKind; label: string; hint: string }[] = [
  { kind: 'physical_tension', label: 'Physical Tension', hint: 'Tight chest, clenched jaw' },
  { kind: 'sensory_overload', label: 'Sensory Overload', hint: 'Too much noise or light' },
  { kind: 'craving_spike', label: 'Craving Spike', hint: 'Sudden, intense urge' },
]

interface Props {
  disabled: boolean
  onSelect: (kind: ScenarioKind) => void
}

export default function TapMatrix({ disabled, onSelect }: Props) {
  return (
    <div className="grid grid-cols-1 gap-2.5">
      {SCENARIOS.map(({ kind, label, hint }) => (
        <button
          key={kind}
          type="button"
          disabled={disabled}
          onClick={() => onSelect(kind)}
          className="group flex min-h-14 items-center justify-between rounded-xl border border-line bg-card px-5 py-3.5 text-left transition hover:border-ember/40 active:scale-[0.98] disabled:opacity-40"
        >
          <span className="flex flex-col">
            <span className="text-base font-medium text-ink">{label}</span>
            <span className="text-xs text-ink-muted">{hint}</span>
          </span>
          <span
            className="h-1.5 w-1.5 rounded-full bg-ink-muted/40 transition group-hover:bg-ember"
            aria-hidden="true"
          />
        </button>
      ))}
    </div>
  )
}
