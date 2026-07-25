import { useCallback, useState } from 'react'
import { signOut } from 'firebase/auth'
import { auth } from '../lib/firebase'
import { generateIntervention, generateCaregiverScript } from '../lib/gemini'
import { logEvent, logCaregiverAlert } from '../lib/events'
import { speak, stopSpeaking } from '../lib/speech'
import { useProactiveEngine } from '../hooks/useProactiveEngine'
import type { InterventionKind, Mood, ScenarioKind } from '../types'
import StatusIndicator from './StatusIndicator'
import PrimaryCard from './PrimaryCard'
import TapMatrix from './TapMatrix'
import MoodRow from './MoodRow'
import BreathingVisualizer from './BreathingVisualizer'
import VoiceIndicator from './VoiceIndicator'
import EmergencyResetButton from './EmergencyResetButton'
import CaregiverAlertButton from './CaregiverAlertButton'
import EvaluatorDock from './EvaluatorDock'

interface Props {
  uid: string
  onBackToLive: () => void
}

export default function PatientScreen({ uid, onBackToLive }: Props) {
  const [mood, setMood] = useState<Mood | null>(null)
  const [script, setScript] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [speaking, setSpeaking] = useState(false)
  const [caregiverBusy, setCaregiverBusy] = useState(false)
  const [proactive, setProactive] = useState(false)

  const active = loading || script !== null

  const runIntervention = useCallback(
    async (kind: InterventionKind, fromEngine = false) => {
      setLoading(true)
      setError(null)
      setProactive(fromEngine)
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
    },
    [mood, uid],
  )

  // The proactive engine and the evaluator dock's "simulate crisis" control both
  // route through this exact function — there is no separate simulated path.
  const triggerProactiveIntervention = useCallback(() => {
    void runIntervention('elevated_stress', true)
  }, [runIntervention])

  const { registerInteraction } = useProactiveEngine(triggerProactiveIntervention, !active)

  const handleReset = () => {
    stopSpeaking()
    setScript(null)
    setError(null)
    setSpeaking(false)
    setProactive(false)
    registerInteraction()
    logEvent(uid, { type: 'reset', mood: null })
  }

  const handleMoodSelect = (m: Mood) => {
    registerInteraction()
    setMood(m)
    logEvent(uid, { type: 'checkin', mood: m })
  }

  const handleCaregiverAlert = useCallback(async () => {
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
  }, [mood, uid])

  const scenarioSelect = (kind: ScenarioKind) => {
    registerInteraction()
    void runIntervention(kind)
  }

  return (
    <div className="relative min-h-screen bg-void text-ink">
      <div className="ember-field" />
      <div className="relative z-10 mx-auto flex min-h-screen max-w-md flex-col gap-7 px-5 py-6 pb-16 lg:max-w-4xl lg:py-10">
        <div className="flex flex-1 flex-col gap-7">
          <div className="flex items-center justify-between">
            <StatusIndicator active={active} />
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={onBackToLive}
                className="min-h-14 px-2 text-xs tracking-wide text-ink-muted transition hover:text-ink"
              >
                ← Voice mode
              </button>
              <button
                type="button"
                onClick={() => signOut(auth)}
                className="min-h-14 px-2 text-xs tracking-wide text-ink-muted transition hover:text-ink"
              >
                Sign out
              </button>
            </div>
          </div>

          {proactive && (script || loading) && (
            <p className="text-xs tracking-wide text-ember">
              Checking in — this looked like a moment worth pausing on.
            </p>
          )}

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

      <EvaluatorDock
        busy={loading || caregiverBusy}
        onOpenVoiceMode={onBackToLive}
        onSimulateCrisis={triggerProactiveIntervention}
        onTestCaregiverSync={handleCaregiverAlert}
      />
    </div>
  )
}
