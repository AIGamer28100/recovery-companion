import { Suspense, lazy, useEffect, useState } from 'react'
import { onAuthStateChanged, type User } from 'firebase/auth'
import { auth } from './lib/firebase'
import { getUserProfile, findLinkedPatient } from './lib/profile'
import type { UserProfile } from './types'
import Login from './components/Login'

// These three views are mutually exclusive per session — a caregiver never loads
// the live voice screen, a patient never loads the dashboard. Splitting them keeps
// the initial download to only what this user actually needs.
const RoleOnboarding = lazy(() => import('./components/RoleOnboarding'))
const LiveApp = lazy(() => import('./components/LiveApp'))
const PatientScreen = lazy(() => import('./components/PatientScreen'))
const CaregiverDashboard = lazy(() => import('./components/CaregiverDashboard'))

/** Matches the app background so a chunk fetch never flashes white at someone in crisis. */
function ScreenFallback() {
  return <div className="min-h-screen bg-void" />
}

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [profileLoading, setProfileLoading] = useState(true)
  const [showTapFallback, setShowTapFallback] = useState(false)
  const [patientUid, setPatientUid] = useState<string | null>(null)

  useEffect(() => {
    return onAuthStateChanged(auth, async (u) => {
      setUser(u)
      setAuthLoading(false)
      if (u) {
        setProfileLoading(true)
        const p = await getUserProfile(u.uid)
        setProfile(p)
        // A caregiver's patient is whoever nominated their email — resolved here
        // rather than stored, so revoking access takes effect immediately.
        if (p?.role === 'caregiver' && u.email) {
          setPatientUid(await findLinkedPatient(u.email))
        }
        setProfileLoading(false)
      } else {
        setProfile(null)
      }
    })
  }, [])

  if (authLoading || (user && profileLoading)) {
    return <div className="min-h-screen bg-void" />
  }

  if (!user) {
    return <Login />
  }

  if (!profile) {
    return (
      <Suspense fallback={<ScreenFallback />}>
      <RoleOnboarding
        uid={user.uid}
        email={user.email ?? ''}
        displayName={user.displayName}
        photoURL={user.photoURL}
        onDone={setProfile}
      />
      </Suspense>
    )
  }

  if (profile.role === 'caregiver') {
    return (
      <Suspense fallback={<ScreenFallback />}>
        <CaregiverDashboard uid={user.uid} profile={profile} patientUid={patientUid} />
      </Suspense>
    )
  }

  // Live voice is the primary experience; the tap-only screen is the fallback
  // for devices without a mic, or when someone can't speak out loud right now.
  if (showTapFallback) {
    return (
      <Suspense fallback={<ScreenFallback />}>
        <PatientScreen uid={user.uid} onBackToLive={() => setShowTapFallback(false)} />
      </Suspense>
    )
  }

  return (
    <Suspense fallback={<ScreenFallback />}>
      <LiveApp
        uid={user.uid}
        profile={profile}
        onOpenFallback={() => setShowTapFallback(true)}
      />
    </Suspense>
  )
}
