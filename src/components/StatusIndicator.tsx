interface Props {
  active: boolean
}

export default function StatusIndicator({ active }: Props) {
  return (
    <div className="flex items-center gap-2 text-xs font-medium tracking-[0.2em] text-ink-muted" role="status">
      <span
        className={`h-2 w-2 rounded-full transition-colors ${active ? 'bg-ember' : 'bg-ink-muted/50'}`}
        aria-hidden="true"
      />
      {active ? 'ACTIVE' : 'CALM'}
    </div>
  )
}
