import { signInWithPopup } from 'firebase/auth'
import { auth, googleProvider } from '../lib/firebase'

export default function Login() {
  const handleSignIn = () => {
    signInWithPopup(auth, googleProvider).catch((err) => {
      console.error('Sign-in failed', err)
    })
  }

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center gap-7 bg-void px-6 text-center text-ink">
      <div className="ember-field" />
      <div className="relative z-10 flex flex-col items-center gap-7">
        <h1 className="font-display text-4xl font-medium tracking-tight text-ink">
          Recovery Companion
        </h1>
        <p className="max-w-[22rem] text-[15px] leading-relaxed text-ink-muted">
          A companion for moments that need one tap, not a form. No typing, no forms —
          just tap what's happening, right now.
        </p>
        <button
          type="button"
          onClick={handleSignIn}
          className="min-h-14 rounded-full bg-ink px-8 text-base font-medium text-void transition active:scale-95"
          aria-label="Continue with Google"
        >
          Continue with Google
        </button>
      </div>
    </div>
  )
}
