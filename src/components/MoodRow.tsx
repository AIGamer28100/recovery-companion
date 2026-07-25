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
    <div className="flex flex-col gap-2">
      <span className="text-xs uppercase tracking-widest text-gray-500">How are you right now?</span>
      <div className="flex justify-between gap-2">
        {MOODS.map(({ mood, emoji, label }) => (
          <button
            key={mood}
            type="button"
            onClick={() => onSelect(mood)}
            aria-label={label}
            aria-pressed={selected === mood}
            className={`flex min-h-14 flex-1 items-center justify-center rounded-xl border text-xl active:scale-95 ${
              selected === mood ? 'border-white bg-white/10' : 'border-gray-800'
            }`}
          >
            <span aria-hidden="true">{emoji}</span>
          </button>
        ))}
      </div>
    </div>
  )
}
