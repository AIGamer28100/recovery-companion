import { useState } from 'react'
import { signOut } from 'firebase/auth'
import { auth } from '../lib/firebase'
import { generateIntervention, generateCaregiverScript } from '../lib/gemini'
import { logEvent, logCaregiverAlert } from '../lib/events'
import { speak, stopSpeaking } from '../lib/speech'
import type { InterventionKind, Mood, ScenarioKind } from '../types'
import StatusIndicator from './StatusIndicator'
import PrimaryCard from './PrimaryCard'
import TapMatrix from './TapMatrix'
import MoodRow from './MoodRow'
import BreathingVisualizer from './BreathingVisualizer'
import VoiceIndicator from './VoiceIndicator'
import EmergencyResetButton from './EmergencyResetButton'
import CaregiverAlertButton from './CaregiverAlertButton'
import LiveConversation from './LiveConversation'

interface Props {
  uid: string
}

export default function PatientScreen({ uid }: Props) {
  const [mood, setMood] = useState<Mood | null>(null)
  const [script, setScript] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [speaking, setSpeaking] = useState(false)
  const [caregiverBusy, setCaregiverBusy] = useState(false)

  const active = loading || script !== null

  const runIntervention = async (kind: InterventionKind) => {
    setLoading(true)
    setError(null)
    try {
      const context = { mood, timeOfDay: new Date().getHours() }
      const text = await generateIntervention(kind, context)
      setScript(text)
      setSpeaking(true)
      speak(text)
      logEvent(uid, { type: kind, mood, script: text })
    } catch (err) {
      console.error('generateIntervention failed', err)
      setError('unreachable')
    } finally {
      setLoading(false)
    }
  }

  const handleReset = () => {
    stopSpeaking()
    setScript(null)
    setError(null)
    setSpeaking(false)
    logEvent(uid, { type: 'reset', mood: null })
  }

  const handleMoodSelect = (m: Mood) => {
    setMood(m)
    logEvent(uid, { type: 'checkin', mood: m })
  }

  const handleCaregiverAlert = async () => {
    setCaregiverBusy(true)
    try {
      const context = { mood, timeOfDay: new Date().getHours() }
      const alertScript = await generateCaregiverScript('elevated_stress', context)
      logCaregiverAlert(uid, { script: alertScript, triggeredBy: 'manual' })
    } catch (err) {
      console.error('generateCaregiverScript failed', err)
    } finally {
      setCaregiverBusy(false)
    }
  }

  const scenarioSelect = (kind: ScenarioKind) => runIntervention(kind)

  return (
    <div className="relative min-h-screen bg-void text-ink">
      <div className="ember-field" />
      <div className="relative z-10 mx-auto flex min-h-screen max-w-md flex-col gap-7 px-5 py-6 lg:max-w-4xl lg:flex-row lg:items-start lg:gap-12 lg:py-10">
        <div className="flex flex-1 flex-col gap-7">
          <div className="flex items-center justify-between">
            <StatusIndicator active={active} />
            <button
              type="button"
              onClick={() => signOut(auth)}
              className="min-h-14 px-2 text-xs tracking-wide text-ink-muted transition hover:text-ink"
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
              <LiveConversation uid={uid} />
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
    </div>
  )
}
