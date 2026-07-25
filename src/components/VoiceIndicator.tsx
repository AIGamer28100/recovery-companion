interface Props {
  speaking: boolean
}

export default function VoiceIndicator({ speaking }: Props) {
  if (!speaking) return null
  return (
    <p className="text-center text-xs text-gray-400" role="status">
      🎤 Voice Assistance Active
    </p>
  )
}
