import { useEffect, useState } from 'react'
import { onAuthStateChanged, signOut, type User } from 'firebase/auth'
import { auth } from './lib/firebase'
import { generateIntervention, generateCaregiverScript } from './lib/gemini'
import { logEvent, logCaregiverAlert } from './lib/events'
import { speak } from './lib/speech'
import type { InterventionKind, Mood, ScenarioKind } from './types'
import Login from './components/Login'
import StatusIndicator from './components/StatusIndicator'
import PrimaryCard from './components/PrimaryCard'
import TapMatrix from './components/TapMatrix'
import MoodRow from './components/MoodRow'
import BreathingVisualizer from './components/BreathingVisualizer'
import VoiceIndicator from './components/VoiceIndicator'
import EmergencyResetButton from './components/EmergencyResetButton'
import CaregiverAlertButton from './components/CaregiverAlertButton'

export default function App() {
  const [user, setUser] = useState<User | null>(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [mood, setMood] = useState<Mood | null>(null)
  const [script, setScript] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [speaking, setSpeaking] = useState(false)
  const [caregiverBusy, setCaregiverBusy] = useState(false)

  useEffect(() => {
    return onAuthStateChanged(auth, (u) => {
      setUser(u)
      setAuthLoading(false)
    })
  }, [])

  const active = loading || script !== null

  const runIntervention = async (kind: InterventionKind) => {
    if (!user) return
    setLoading(true)
    setError(null)
    try {
      const context = { mood, timeOfDay: new Date().getHours() }
      const text = await generateIntervention(kind, context)
      setScript(text)
      setSpeaking(true)
      speak(text)
      logEvent(user.uid, { type: kind, mood, script: text })
    } catch (err) {
      console.error('generateIntervention failed', err)
      setError('unreachable')
    } finally {
      setLoading(false)
    }
  }

  const handleReset = () => {
    setScript(null)
    setError(null)
    setSpeaking(false)
    if (user) logEvent(user.uid, { type: 'reset', mood: null })
  }

  const handleMoodSelect = (m: Mood) => {
    setMood(m)
    if (user) logEvent(user.uid, { type: 'checkin', mood: m })
  }

  const handleCaregiverAlert = async () => {
    if (!user) return
    setCaregiverBusy(true)
    try {
      const context = { mood, timeOfDay: new Date().getHours() }
      const alertScript = await generateCaregiverScript('elevated_stress', context)
      logCaregiverAlert(user.uid, { script: alertScript, triggeredBy: 'manual' })
    } catch (err) {
      console.error('generateCaregiverScript failed', err)
    } finally {
      setCaregiverBusy(false)
    }
  }

  if (authLoading) {
    return <div className="min-h-screen bg-black" />
  }

  if (!user) {
    return <Login />
  }

  const scenarioSelect = (kind: ScenarioKind) => runIntervention(kind)

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col gap-6 bg-black px-5 py-4 text-white lg:max-w-4xl lg:flex-row lg:items-start lg:gap-10">
      <div className="flex flex-1 flex-col gap-6">
        <div className="flex items-center justify-between">
          <StatusIndicator active={active} />
          <button
            type="button"
            onClick={() => signOut(auth)}
            className="min-h-14 px-2 text-xs text-gray-500"
          >
            Sign out
          </button>
        </div>

        <PrimaryCard
          loading={loading}
          error={error}
          script={script}
          onSpeakAgain={() => script && speak(script)}
        />

        <VoiceIndicator speaking={speaking && !loading} />

        {!active && (
          <>
            <TapMatrix disabled={loading} onSelect={scenarioSelect} />
            <BreathingVisualizer />
            <MoodRow selected={mood} onSelect={handleMoodSelect} />
          </>
        )}

        <div className="mt-auto flex flex-col gap-3 pb-4">
          <EmergencyResetButton onReset={handleReset} />
          <CaregiverAlertButton disabled={caregiverBusy} onTrigger={handleCaregiverAlert} />
        </div>
      </div>
    </div>
  )
}
