import type { CSSProperties } from 'react'

interface ReactiveOrbProps {
  /** How fast the orb breathes/pulses in the current call state. Purely presentational. */
  orbSpeed: string
  /** Collapses the orb out of the way so it never sits on top of the camera view. */
  cameraOn: boolean
}

/**
 * The reactive orb: idle and slow at rest, alive during a call. It collapses
 * to a bottom glow bar once the camera is on — see `OrbGlowBar` — so it never
 * sits on top of the thing the user is trying to show.
 */
export default function ReactiveOrb({ orbSpeed, cameraOn }: ReactiveOrbProps) {
  return (
    <div
      className={`flex flex-1 items-center justify-center py-6 transition-opacity duration-500 ${
        cameraOn ? 'pointer-events-none opacity-0' : 'opacity-100'
      }`}
      aria-hidden={cameraOn}
    >
      <div
        className="relative flex h-48 w-48 items-center justify-center sm:h-56 sm:w-56"
        style={{ '--orb-speed': orbSpeed } as CSSProperties}
      >
        <div
          className="orb-glow absolute -inset-6 rounded-full blur-3xl"
          style={{
            background: 'radial-gradient(circle, var(--color-ember) 0%, transparent 70%)',
            opacity: 0.4,
          }}
          aria-hidden="true"
        />
        <div
          className="orb-ring absolute inset-0 rounded-full border border-ember/40"
          style={{ animationDelay: '0s' }}
          aria-hidden="true"
        />
        <div
          className="orb-ring absolute inset-0 rounded-full border border-ember/25"
          style={{ animationDelay: 'calc(var(--orb-speed) / 3)' }}
          aria-hidden="true"
        />
        <div
          className="orb-ring absolute inset-0 rounded-full border border-ember/15"
          style={{ animationDelay: 'calc(var(--orb-speed) / 3 * 2)' }}
          aria-hidden="true"
        />
        <div
          className="orb-sheen absolute h-32 w-32 rounded-full opacity-50 sm:h-36 sm:w-36"
          style={{
            background: 'conic-gradient(from 0deg, transparent 0%, var(--color-ember) 20%, transparent 40%)',
            animationDuration: 'calc(var(--orb-speed) * 3)',
          }}
          aria-hidden="true"
        />
        <div
          className="orb-core relative h-32 w-32 rounded-full sm:h-36 sm:w-36"
          style={{
            background: 'radial-gradient(circle at 35% 28%, #f3d5a3 0%, var(--color-ember) 55%, #8f5f2a 100%)',
            boxShadow: '0 0 70px 8px var(--color-ember-soft), inset 0 0 30px rgba(0,0,0,0.25)',
          }}
          aria-hidden="true"
        />
      </div>
    </div>
  )
}

/**
 * With the camera on, the orb becomes an ambient strip of light so the
 * companion still feels present without covering the view. Rendered by the
 * caller only when `live && cameraOn`.
 */
export function OrbGlowBar({ orbSpeed }: { orbSpeed: string }) {
  return (
    <div
      className="flex h-8 w-full max-w-md items-end justify-center"
      style={{ '--orb-speed': orbSpeed } as CSSProperties}
      aria-hidden="true"
    >
      <div
        className="orb-glow h-1.5 w-48 rounded-full blur-[6px]"
        style={{
          background: 'linear-gradient(90deg, transparent 0%, var(--color-ember) 50%, transparent 100%)',
        }}
      />
    </div>
  )
}
