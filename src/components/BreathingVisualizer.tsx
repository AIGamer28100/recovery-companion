export default function BreathingVisualizer() {
  return (
    <div className="flex flex-col items-center gap-2 py-4">
      <div
        className="h-16 w-16 rounded-full border border-gray-600 bg-white/10"
        style={{ animation: 'breathe 8s ease-in-out infinite' }}
        aria-hidden="true"
      />
      <style>{`
        @keyframes breathe {
          0%, 100% { transform: scale(0.6); opacity: 0.5; }
          50% { transform: scale(1.3); opacity: 1; }
        }
      `}</style>
      <p className="text-xs text-gray-500">Breathe with the circle — in as it grows, out as it shrinks</p>
    </div>
  )
}
