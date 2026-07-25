interface Props {
  speaking: boolean
}

export default function VoiceIndicator({ speaking }: Props) {
  if (!speaking) return null
  return (
    <p className="text-center text-xs tracking-wide text-ink-muted" role="status">
      🎤 Voice Assistance Active
    </p>
  )
}
