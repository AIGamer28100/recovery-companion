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
    <div className="grid grid-cols-1 gap-3">
      {SCENARIOS.map(({ kind, label, hint }) => (
        <button
          key={kind}
          type="button"
          disabled={disabled}
          onClick={() => onSelect(kind)}
          className="min-h-14 rounded-xl border border-gray-700 bg-gray-900 px-5 py-3 text-left active:scale-[0.98] disabled:opacity-40"
        >
          <span className="block text-base font-medium text-white">{label}</span>
          <span className="block text-xs text-gray-500">{hint}</span>
        </button>
      ))}
    </div>
  )
}
