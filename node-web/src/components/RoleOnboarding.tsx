import { useState } from 'react'
import { createPatientProfile, createCaregiverProfile, findLinkedPatient } from '../lib/profile'
import type { UserProfile } from '../types'

interface Props {
  uid: string
  email: string
  displayName: string | null
  photoURL: string | null
  onDone: (profile: UserProfile) => void
}

export default function RoleOnboarding({ uid, email, displayName, photoURL, onDone }: Props) {
  const identity = { displayName, photoURL }
  const [step, setStep] = useState<'choose' | 'link' | 'support'>('choose')
  const [caregiverEmail, setCaregiverEmail] = useState('')
  const [contactName, setContactName] = useState('')
  const [contactPhone, setContactPhone] = useState('')
  const [busy, setBusy] = useState(false)
  const [notFound, setNotFound] = useState(false)

  // Patients go through a support step before landing in the app: someone to
  // call matters most at the exact moment they're least able to go looking.
  const choosePatient = () => setStep('support')

  const finishPatient = async (contact: { name: string; phone: string }) => {
    setBusy(true)
    const nominated = caregiverEmail.trim().toLowerCase()
    await createPatientProfile(uid, email, contact, identity, nominated)
    onDone({
      role: 'patient',
      email,
      displayName,
      photoURL,
      emergencyContact: contact,
      linkedCaregiverEmails: nominated ? [nominated] : [],
      createdAt: null,
    })
  }

  const chooseCaregiver = async () => {
    // No typing and no lookup-by-email: we find whoever nominated THIS account.
    setBusy(true)
    setNotFound(false)
    const patientUid = await findLinkedPatient(email)
    if (!patientUid) {
      setBusy(false)
      setNotFound(true)
      setStep('link')
      return
    }
    await createCaregiverProfile(uid, email, identity)
    onDone({ role: 'caregiver', email, displayName, photoURL, createdAt: null })
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

        {step === 'support' && (
          <>
            <h1 className="font-display text-2xl font-medium">Who should we reach?</h1>
            <p className="text-sm leading-relaxed text-ink-muted">
              Add one person you&apos;d want called on a hard night. They&apos;ll be one tap away
              inside the app, and if you invite them to sign up as your caregiver, they&apos;ll get
              alerts too.
            </p>
            <div className="flex w-full flex-col gap-3">
              <label htmlFor="contact-name" className="sr-only">
                Their name
              </label>
              <input
                id="contact-name"
                type="text"
                value={contactName}
                onChange={(e) => setContactName(e.target.value)}
                placeholder="Their name"
                aria-describedby="contact-required-hint"
                className="min-h-14 w-full rounded-xl border border-line bg-card px-4 text-center text-ink placeholder:text-ink-muted focus:border-ember focus:outline-none"
              />
              <label htmlFor="contact-phone" className="sr-only">
                Their phone number
              </label>
              <input
                id="contact-phone"
                type="tel"
                value={contactPhone}
                onChange={(e) => setContactPhone(e.target.value)}
                placeholder="Their phone number"
                aria-describedby="contact-required-hint"
                className="min-h-14 w-full rounded-xl border border-line bg-card px-4 text-center text-ink placeholder:text-ink-muted focus:border-ember focus:outline-none"
              />
              <label htmlFor="caregiver-email" className="sr-only">
                Caregiver's email (optional)
              </label>
              <input
                id="caregiver-email"
                type="email"
                value={caregiverEmail}
                onChange={(e) => setCaregiverEmail(e.target.value)}
                placeholder="Their Google email (optional)"
                className="min-h-14 w-full rounded-xl border border-line bg-card px-4 text-center text-ink placeholder:text-ink-muted focus:border-ember focus:outline-none"
              />
              <button
                type="button"
                disabled={busy || !contactName.trim() || !contactPhone.trim()}
                onClick={() =>
                  finishPatient({ name: contactName.trim(), phone: contactPhone.trim() })
                }
                className="min-h-14 w-full rounded-xl bg-ink text-sm font-semibold text-void transition active:scale-[0.98] disabled:opacity-40"
              >
                {busy ? 'Saving…' : 'Save and continue'}
              </button>
              <p id="contact-required-hint" className="text-xs leading-relaxed text-ink-muted/80">
                A contact is required — on a hard night you shouldn&apos;t have to go looking for a
                number. Add their Google email too and they can sign in as your caregiver to see
                your patterns and get alerts. Only you can grant that, and only to an address you
                enter here.
              </p>
            </div>
          </>
        )}

        {step === 'link' && (
          <div role="status" aria-live="polite" className="contents">
            <h1 className="font-display text-2xl font-medium">No invitation yet</h1>
            <p className="text-sm leading-relaxed text-ink-muted">
              {notFound
                ? "Nobody has added this email as their caregiver yet. For their privacy, only the person in recovery can grant that — ask them to add "
                : 'Ask the person you support to add '}
              <span className="text-ink">{email}</span>
              {' '}in their app, then sign in again.
            </p>
            <button
              type="button"
              onClick={() => {
                setNotFound(false)
                setStep('choose')
              }}
              className="min-h-14 w-full rounded-xl border border-line text-sm font-medium text-ink transition hover:border-ember/40"
            >
              Back
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
