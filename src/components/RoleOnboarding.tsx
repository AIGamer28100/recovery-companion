import { useState } from 'react'
import { createPatientProfile, createCaregiverProfileAndLink } from '../lib/profile'
import type { UserProfile } from '../types'

interface Props {
  uid: string
  email: string
  onDone: (profile: UserProfile) => void
}

export default function RoleOnboarding({ uid, email, onDone }: Props) {
  const [step, setStep] = useState<'choose' | 'link'>('choose')
  const [patientEmail, setPatientEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [notFound, setNotFound] = useState(false)

  const choosePatient = async () => {
    setBusy(true)
    await createPatientProfile(uid, email)
    onDone({ role: 'patient', email, linkedCaregiverUids: [], createdAt: null })
  }

  const chooseCaregiver = () => setStep('link')

  const submitLink = async () => {
    if (!patientEmail.trim()) return
    setBusy(true)
    setNotFound(false)
    const { linked } = await createCaregiverProfileAndLink(uid, email, patientEmail)
    setBusy(false)
    if (!linked) {
      setNotFound(true)
      return
    }
    onDone({ role: 'caregiver', email, linkedPatientUid: null, createdAt: null })
  }

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center gap-7 bg-void px-6 text-center text-ink">
      <div className="ember-field" />
      <div className="relative z-10 flex w-full max-w-sm flex-col items-center gap-6">
        {step === 'choose' && (
          <>
            <h1 className="font-display text-2xl font-medium">Who's using this?</h1>
            <p className="text-sm text-ink-muted">
              This helps us tailor what you see. You can&apos;t change this later in this build.
            </p>
            <div className="flex w-full flex-col gap-3">
              <button
                type="button"
                disabled={busy}
                onClick={choosePatient}
                className="min-h-14 w-full rounded-xl bg-ink text-sm font-semibold text-void transition active:scale-[0.98] disabled:opacity-40"
              >
                I'm the person in recovery
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={chooseCaregiver}
                className="min-h-14 w-full rounded-xl border border-line text-sm font-medium text-ink transition hover:border-ember/40 disabled:opacity-40"
              >
                I'm a caregiver
              </button>
            </div>
          </>
        )}

        {step === 'link' && (
          <>
            <h1 className="font-display text-2xl font-medium">Link to your person</h1>
            <p className="text-sm text-ink-muted">
              Enter the email they used to sign in here, so you can see their patterns and get
              scripts tailored to what&apos;s actually going on with them.
            </p>
            <label htmlFor="patient-email" className="sr-only">
              Patient&apos;s email
            </label>
            <input
              id="patient-email"
              type="email"
              value={patientEmail}
              onChange={(e) => setPatientEmail(e.target.value)}
              placeholder="their.email@gmail.com"
              className="min-h-14 w-full rounded-xl border border-line bg-card px-4 text-center text-ink placeholder:text-ink-muted focus:border-ember focus:outline-none"
            />
            {notFound && (
              <p className="text-xs text-ink-muted">
                No account found with that email yet. They need to sign in at least once first.
              </p>
            )}
            <button
              type="button"
              disabled={busy || !patientEmail.trim()}
              onClick={submitLink}
              className="min-h-14 w-full rounded-xl bg-ink text-sm font-semibold text-void transition active:scale-[0.98] disabled:opacity-40"
            >
              {busy ? 'Linking…' : 'Link account'}
            </button>
          </>
        )}
      </div>
    </div>
  )
}
