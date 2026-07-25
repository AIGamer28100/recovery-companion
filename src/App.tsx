import { useEffect, useState } from 'react'
import { onAuthStateChanged, type User } from 'firebase/auth'
import { auth } from './lib/firebase'
import { getUserProfile } from './lib/profile'
import type { UserProfile } from './types'
import Login from './components/Login'
import RoleOnboarding from './components/RoleOnboarding'
import LiveApp from './components/LiveApp'
import PatientScreen from './components/PatientScreen'
import CaregiverDashboard from './components/CaregiverDashboard'

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [profileLoading, setProfileLoading] = useState(true)
  const [showTapFallback, setShowTapFallback] = useState(false)

  useEffect(() => {
    return onAuthStateChanged(auth, async (u) => {
      setUser(u)
      setAuthLoading(false)
      if (u) {
        setProfileLoading(true)
        const p = await getUserProfile(u.uid)
        setProfile(p)
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
      <RoleOnboarding uid={user.uid} email={user.email ?? ''} onDone={setProfile} />
    )
  }

  if (profile.role === 'caregiver') {
    return <CaregiverDashboard uid={user.uid} profile={profile} />
  }

  // Live voice is the primary experience; the tap-only screen is the fallback
  // for devices without a mic, or when someone can't speak out loud right now.
  if (showTapFallback) {
    return <PatientScreen uid={user.uid} onBackToLive={() => setShowTapFallback(false)} />
  }

  return (
    <LiveApp
      uid={user.uid}
      profile={profile}
      onOpenFallback={() => setShowTapFallback(true)}
    />
  )
}
