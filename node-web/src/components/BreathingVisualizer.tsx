export default function BreathingVisualizer() {
  return (
    <div className="flex flex-col items-center gap-3 py-3">
      <div className="relative flex h-20 w-20 items-center justify-center">
        <div
          className="absolute inset-0 rounded-full border border-ember/30"
          style={{ animation: 'breathe-ring 8s ease-in-out infinite' }}
          aria-hidden="true"
        />
        <div
          className="h-9 w-9 rounded-full bg-ember/80"
          style={{ animation: 'breathe-core 8s ease-in-out infinite' }}
          aria-hidden="true"
        />
      </div>
      <style>{`
        @keyframes breathe-ring {
          0%, 100% { transform: scale(0.7); opacity: 0.3; }
          50% { transform: scale(1.4); opacity: 0.8; }
        }
        @keyframes breathe-core {
          0%, 100% { transform: scale(0.75); opacity: 0.6; }
          50% { transform: scale(1.15); opacity: 1; }
        }
      `}</style>
      <p className="text-xs text-ink-muted">Breathe with it — in as it grows, out as it shrinks</p>
    </div>
  )
}
