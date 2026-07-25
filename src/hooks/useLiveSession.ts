import { useCallback, useEffect, useRef, useState } from 'react'
import { startAudioConversation } from 'firebase/ai'
import type { AudioConversationController, LiveSession } from 'firebase/ai'
import { connectLiveSession, VISION_CHECK_PROMPT } from '../lib/geminiLive'
import { teeSession } from '../lib/liveTee'
import { VideoFrameStreamer } from '../lib/videoStream'
import { logEvent, logCaregiverAlert } from '../lib/events'
import { recordRelapseIncident } from '../lib/incidents'
import { buildContinuityBriefing, saveSessionTranscript } from '../lib/sessionMemory'
import {
  detectCameraAvailability,
  describeCameraForModel,
  type CameraAvailability,
} from '../lib/cameraAvailability'
import type { RelapseStage } from '../lib/safetyTools'
import { describeSupportForModel, type EmergencyContact } from '../lib/emergencyContacts'

export type Status = 'idle' | 'connecting' | 'live' | 'error'

/** How often the vision coach considers nudging. */
const COACH_TICK_MS = 5000
/**
 * Both sides must have been quiet this long before a nudge is even considered.
 * Generous on purpose: someone going quiet is usually mid-exercise or thinking,
 * and a companion that pipes up every few seconds is worse than one that waits.
 */
const QUIET_BEFORE_NUDGE_MS = 25000
/** Hard floor between nudges, so a long silence can't turn into a drip of prompts. */
const MIN_NUDGE_GAP_MS = 60000

export interface TranscriptLine {
  role: 'you' | 'companion'
  text: string
}

interface UseLiveSessionParams {
  uid: string
  emergencyContact: EmergencyContact | null
  hasLinkedCaregiver: boolean
}

/**
 * Owns the entire live-session lifecycle: connecting the mic, tee-ing the
 * transcript, the camera stream + frame streamer, the vision-coach nudge
 * timer, and the relapse-risk function-calling handler. Returns a clean
 * interface for a presentational component to render.
 */
export function useLiveSession({ uid, emergencyContact, hasLinkedCaregiver }: UseLiveSessionParams) {
  const [status, setStatus] = useState<Status>('idle')
  const [cameraOn, setCameraOn] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [lines, setLines] = useState<TranscriptLine[]>([])
  const [incidentStage, setIncidentStage] = useState<RelapseStage | null>(null)
  const [camera, setCamera] = useState<CameraAvailability>({
    state: 'unsupported',
    canOffer: false,
  })

  const sessionRef = useRef<LiveSession | null>(null)
  const controllerRef = useRef<AudioConversationController | null>(null)
  const streamerRef = useRef<VideoFrameStreamer | null>(null)
  const cameraStreamRef = useRef<MediaStream | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)

  const lastActivityRef = useRef<number>(0)
  const lastNudgeRef = useRef<number>(0)
  const coachTimerRef = useRef<number | null>(null)
  const cameraOnRef = useRef(false)
  /**
   * Bumped by every endCall/unmount. `startCall` re-checks it after each await so
   * a session opened during teardown can't resurrect itself — without this, tapping
   * "Start talking" then immediately navigating away leaves an orphaned live mic
   * session and a stray interval running against an unmounted component.
   */
  const callGenerationRef = useRef(0)

  const stopVisionCoach = useCallback(() => {
    if (coachTimerRef.current !== null) {
      window.clearInterval(coachTimerRef.current)
      coachTimerRef.current = null
    }
  }, [])

  /**
   * Nudges the model to re-check the camera, but only during a genuine lull —
   * never while either side is mid-sentence. Without the silence gate this
   * becomes a companion that talks over you every few seconds.
   */
  const startVisionCoach = useCallback(() => {
    stopVisionCoach()
    coachTimerRef.current = window.setInterval(() => {
      const session = sessionRef.current
      if (!session || session.isClosed || !cameraOnRef.current) return

      const now = Date.now()
      const quietFor = now - lastActivityRef.current
      const sinceNudge = now - lastNudgeRef.current
      if (quietFor < QUIET_BEFORE_NUDGE_MS || sinceNudge < MIN_NUDGE_GAP_MS) return

      lastNudgeRef.current = now
      void session.sendTextRealtime(VISION_CHECK_PROMPT).catch(() => {
        /* session closing — nothing to do */
      })
    }, COACH_TICK_MS)
  }, [stopVisionCoach])

  const stopCamera = useCallback(() => {
    streamerRef.current?.stop()
    streamerRef.current = null
    cameraStreamRef.current?.getTracks().forEach((t) => t.stop())
    cameraStreamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    cameraOnRef.current = false
    setCameraOn(false)
  }, [])

  const linesRef = useRef<TranscriptLine[]>([])
  linesRef.current = lines

  const endCall = useCallback(async () => {
    callGenerationRef.current += 1
    stopVisionCoach()
    stopCamera()
    // Persist the conversation so the next session can pick up where this left off.
    const transcript = linesRef.current
      .map((l) => `${l.role === 'you' ? 'Them' : 'You'}: ${l.text}`)
      .join('\n')
    void saveSessionTranscript(uid, transcript).catch((err) =>
      console.warn('Could not save session transcript', err),
    )
    try {
      await controllerRef.current?.stop()
      await sessionRef.current?.close()
    } catch {
      // already torn down
    }
    controllerRef.current = null
    sessionRef.current = null
    setStatus('idle')
  }, [stopCamera, stopVisionCoach, uid])

  // Never leave the mic or camera running if this unmounts.
  useEffect(() => {
    return () => {
      void endCall()
    }
  }, [endCall])

  // Probe for a usable camera up front (without triggering a permission prompt)
  // so the companion never offers something this device can't do. Re-checked when
  // the permission changes, e.g. the user unblocks it mid-call.
  useEffect(() => {
    let cancelled = false
    const refresh = () => {
      void detectCameraAvailability().then((result) => {
        if (!cancelled) setCamera(result)
      })
    }
    refresh()

    let permStatus: PermissionStatus | undefined
    void navigator.permissions
      ?.query({ name: 'camera' as PermissionName })
      .then((status) => {
        permStatus = status
        status.addEventListener('change', refresh)
      })
      .catch(() => {
        /* Permissions API doesn't support 'camera' here — the initial probe stands. */
      })

    navigator.mediaDevices?.addEventListener?.('devicechange', refresh)
    return () => {
      cancelled = true
      permStatus?.removeEventListener('change', refresh)
      navigator.mediaDevices?.removeEventListener?.('devicechange', refresh)
    }
  }, [])

  // Transcripts arrive as small fragments ("How a", "re yo", "u today?"), so
  // consecutive chunks from the same speaker are merged into one line.
  const appendTranscript = useCallback((role: TranscriptLine['role'], chunk: string) => {
    setLines((prev) => {
      const last = prev[prev.length - 1]
      if (last?.role === role) {
        return [...prev.slice(0, -1), { role, text: last.text + chunk }]
      }
      return [...prev.slice(-40), { role, text: chunk }]
    })
  }, [])

  const startCall = async () => {
    setStatus('connecting')
    setErrorMsg(null)
    setLines([])
    const generation = callGenerationRef.current
    const isStale = () => generation !== callGenerationRef.current
    try {
      const session = await connectLiveSession()
      if (isStale()) {
        void session.close().catch(() => {})
        return
      }
      sessionRef.current = session

      // startAudioConversation claims the session's single receive() consumer,
      // so tee the stream: audio still flows to playback untouched, and we get
      // a copy of every message for the live transcript.
      const teed = teeSession(session, (message) => {
        if (message.type !== 'serverContent') return
        if (message.inputTranscription?.text) {
          lastActivityRef.current = Date.now()
          appendTranscript('you', message.inputTranscription.text)
        }
        if (message.outputTranscription?.text) {
          lastActivityRef.current = Date.now()
          appendTranscript('companion', message.outputTranscription.text)
        }
      })

      const controller = await startAudioConversation(teed, {
        functionCallingHandler: async (functionCalls) => {
          const call = functionCalls[0]
          if (call?.name !== 'flagRelapseRisk') {
            return { name: call?.name ?? 'unknown', response: { ok: false } }
          }
          const args = call.args as { stage?: RelapseStage; observation?: string }
          const stage = args.stage === 'escalated' ? 'escalated' : 'intervening'
          try {
            await recordRelapseIncident(uid, stage, args.observation ?? '', videoRef.current)
            if (stage === 'escalated') {
              await logCaregiverAlert(uid, {
                script: `Urgent: ${args.observation ?? 'possible substance use observed on camera'}`,
                triggeredBy: 'relapse_risk',
              })
            }
            setIncidentStage(stage)
            return {
              name: call.name,
              response: {
                ok: true,
                stage,
                caregiverNotified: stage === 'escalated',
              },
            }
          } catch (err) {
            console.error('Failed to record relapse incident', err)
            return { name: call.name, response: { ok: false } }
          }
        },
      })

      if (isStale()) {
        void controller.stop().catch(() => {})
        void session.close().catch(() => {})
        return
      }
      controllerRef.current = controller

      lastActivityRef.current = Date.now()
      startVisionCoach()

      // Opens every call as a continuation: the companion greets them, knows the
      // time of day, and remembers the last conversation.
      // Re-probe at call time rather than trusting mount-time state — they may
      // have plugged in a webcam or changed the permission since.
      const cameraNow = await detectCameraAvailability()
      setCamera(cameraNow)

      const briefing = await buildContinuityBriefing(uid)
      void session
        .sendTextRealtime(
          `${briefing}\n\n[Camera: ${describeCameraForModel(cameraNow, false)}]` +
            `\n\n[Support available to them: ${describeSupportForModel(
              emergencyContact,
              hasLinkedCaregiver,
            )}]`,
        )
        .catch(() => {})

      setStatus('live')
      logEvent(uid, { type: 'live_conversation', mood: null })
    } catch (err) {
      console.error('Live conversation failed to start', err)
      setErrorMsg(
        err instanceof DOMException
          ? 'Microphone access is blocked. Allow it in your browser and try again.'
          : "Couldn't open the line. Check your connection and try again.",
      )
      setStatus('error')
      await endCall()
      setStatus('error')
    }
  }

  const toggleCamera = async () => {
    if (cameraOn) {
      stopCamera()
      void sessionRef.current
        ?.sendTextRealtime(
          `[Silent director note, not from the user. Their camera is now OFF — you can no longer ` +
            `see them. Do not comment on it. Keep coaching by voice alone. ${describeCameraForModel(camera, false)}]`,
        )
        .catch(() => {})
      return
    }
    const session = sessionRef.current
    if (!session) return
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 1280 } },
      })
      cameraStreamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }
      const streamer = new VideoFrameStreamer(session, videoRef.current!)
      streamer.start()
      streamerRef.current = streamer
      cameraOnRef.current = true
      // Give the model a moment of real video before the first nudge.
      lastNudgeRef.current = Date.now()
      setCameraOn(true)
      // Let the model know it can see now, so it can coach visually and stop
      // asking for the camera.
      void session
        .sendTextRealtime(
          `[Silent director note, not from the user. ${describeCameraForModel(camera, true)} ` +
            'Do not announce this or thank them; just start using it. Say nothing right now unless ' +
            'you were mid-exercise with them.]',
        )
        .catch(() => {})
    } catch (err) {
      console.error('Camera unavailable', err)
      setErrorMsg('Camera access is blocked, but the conversation is still going.')
      stopCamera()
    }
  }

  const dismissIncident = useCallback(() => setIncidentStage(null), [])

  return {
    status,
    cameraOn,
    camera,
    errorMsg,
    lines,
    incidentStage,
    videoRef,
    startCall,
    endCall,
    toggleCamera,
    dismissIncident,
  }
}
