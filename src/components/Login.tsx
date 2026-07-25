import { signInWithPopup } from 'firebase/auth'
import { auth, googleProvider } from '../lib/firebase'

export default function Login() {
  const handleSignIn = () => {
    signInWithPopup(auth, googleProvider).catch((err) => {
      console.error('Sign-in failed', err)
    })
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 bg-black px-6 text-center text-white">
      <h1 className="text-2xl font-semibold">Recovery Companion</h1>
      <p className="max-w-xs text-sm text-gray-400">
        A zero-typing companion for moments that need one tap, not a form.
      </p>
      <button
        type="button"
        onClick={handleSignIn}
        className="min-h-14 rounded-full bg-white px-8 text-base font-medium text-black active:scale-95"
        aria-label="Continue with Google"
      >
        Continue with Google
      </button>
    </div>
  )
}
