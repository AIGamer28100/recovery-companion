import type { Mood } from '../types'

const MOODS: { mood: Mood; emoji: string; label: string }[] = [
  { mood: 'calm', emoji: '🙂', label: 'Calm' },
  { mood: 'anxious', emoji: '😰', label: 'Anxious' },
  { mood: 'irritable', emoji: '😠', label: 'Irritable' },
  { mood: 'low', emoji: '😔', label: 'Low' },
  { mood: 'overwhelmed', emoji: '🥵', label: 'Overwhelmed' },
]

interface Props {
  selected: Mood | null
  onSelect: (mood: Mood) => void
}

export default function MoodRow({ selected, onSelect }: Props) {
  return (
    <div className="flex flex-col gap-2.5">
      <span className="text-xs font-medium tracking-[0.2em] text-ink-muted">
        HOW ARE YOU RIGHT NOW?
      </span>
      <div className="flex justify-between gap-2">
        {MOODS.map(({ mood, emoji, label }) => (
          <button
            key={mood}
            type="button"
            onClick={() => onSelect(mood)}
            aria-label={label}
            aria-pressed={selected === mood}
            className={`flex min-h-14 flex-1 items-center justify-center rounded-xl border text-xl transition active:scale-95 ${
              selected === mood ? 'border-ember bg-ember-soft' : 'border-line bg-card hover:border-ink-muted/40'
            }`}
          >
            <span aria-hidden="true">{emoji}</span>
          </button>
        ))}
      </div>
    </div>
  )
}
