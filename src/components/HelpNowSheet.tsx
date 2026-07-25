import { useState } from 'react'
import { PUBLIC_HELPLINES, toTelHref, type EmergencyContact } from '../lib/emergencyContacts'

interface Props {
  contact: EmergencyContact | null
}

/**
 * A always-reachable list of real people and helplines to call.
 *
 * Deliberately never buried behind a menu: the moment someone needs this is the
 * moment they have the least capacity to go hunting for it.
 */
export default function HelpNowSheet({ contact }: Props) {
  const [open, setOpen] = useState(false)

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="min-h-14 rounded-full border border-red-500/40 bg-red-500/10 px-5 text-xs font-semibold tracking-wide text-red-200 transition hover:border-red-500/70"
      >
        Get help now
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-4 backdrop-blur-sm sm:items-center"
          role="dialog"
          aria-modal="true"
          aria-label="Get help now"
        >
          <div className="w-full max-w-md rounded-3xl border border-line bg-card p-6">
            <h2 className="mb-1 font-display text-xl">Get help now</h2>
            <p className="mb-5 text-sm text-ink-muted">
              Tap any of these to call straight away.
            </p>

            <div className="flex flex-col gap-2.5">
              {contact && (
                <a
                  href={toTelHref(contact.phone)}
                  className="flex min-h-14 flex-col justify-center rounded-xl border border-ember bg-ember-soft px-5 py-3 text-left"
                >
                  <span className="text-base font-medium text-ink">Call {contact.name}</span>
                  <span className="text-xs text-ink-muted">
                    {contact.phone} · your emergency contact
                  </span>
                </a>
              )}

              {PUBLIC_HELPLINES.map((line) => (
                <a
                  key={line.phone}
                  href={toTelHref(line.phone)}
                  className="flex min-h-14 flex-col justify-center rounded-xl border border-line px-5 py-3 text-left transition hover:border-ink-muted/60"
                >
                  <span className="text-base font-medium text-ink">
                    {line.name} · {line.phone}
                  </span>
                  <span className="text-xs text-ink-muted">{line.detail}</span>
                </a>
              ))}
            </div>

            <button
              type="button"
              onClick={() => setOpen(false)}
              className="mt-5 min-h-14 w-full rounded-xl border border-line text-sm text-ink-muted transition hover:text-ink"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </>
  )
}
