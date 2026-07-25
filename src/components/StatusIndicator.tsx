interface Props {
  active: boolean
}

export default function StatusIndicator({ active }: Props) {
  return (
    <div
      className="flex items-center justify-center gap-2 py-3 text-xs uppercase tracking-widest text-gray-400"
      role="status"
    >
      <span
        className={`h-2 w-2 rounded-full ${active ? 'bg-white animate-pulse' : 'bg-gray-600'}`}
        aria-hidden="true"
      />
      {active ? 'Active' : 'Calm'}
    </div>
  )
}
