import { useEffect, useRef } from 'react'
import type { TranscriptLine } from '../../hooks/useLiveSession'

interface LiveTranscriptProps {
  lines: TranscriptLine[]
}

/** The live caption overlay: scrolls to the newest line as the transcript grows. */
export default function LiveTranscript({ lines }: LiveTranscriptProps) {
  const transcriptEndRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    transcriptEndRef.current?.scrollIntoView({ block: 'end' })
  }, [lines])

  return (
    <div
      className="w-full max-w-md animate-[caption-fade-in_0.3s_ease-out] rounded-3xl bg-void/40 px-4 py-3 text-left backdrop-blur-md motion-reduce:animate-none"
      role="log"
      aria-live="polite"
      aria-label="Live transcript"
    >
      <div className="max-h-40 overflow-y-auto">
        {lines.length === 0 ? (
          <p className="text-sm text-ink-muted/80">Your words and mine will show up here as we talk.</p>
        ) : (
          <div className="flex flex-col gap-2.5">
            {lines.map((line, i) => (
              <p key={i} className="text-sm leading-relaxed">
                <span
                  className={`mr-2 text-[10px] font-semibold tracking-[0.15em] ${
                    line.role === 'you' ? 'text-ink-muted' : 'text-ember'
                  }`}
                >
                  {line.role === 'you' ? 'YOU' : 'COMPANION'}
                </span>
                <span className={line.role === 'you' ? 'text-ink-muted' : 'font-medium text-ink'}>
                  {line.text}
                </span>
              </p>
            ))}
            <div ref={transcriptEndRef} />
          </div>
        )}
      </div>
    </div>
  )
}
