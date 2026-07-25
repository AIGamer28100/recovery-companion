import { addDoc, collection, serverTimestamp } from 'firebase/firestore'
import { db } from './firebase'
import type { RelapseStage } from './safetyTools'

/** Evidence frames stay small — Firestore documents are capped at 1 MB. */
const EVIDENCE_WIDTH = 320
const EVIDENCE_QUALITY = 0.45

export function captureFrame(video: HTMLVideoElement | null): string | null {
  if (!video?.videoWidth) return null
  const canvas = document.createElement('canvas')
  const scale = EVIDENCE_WIDTH / video.videoWidth
  canvas.width = EVIDENCE_WIDTH
  canvas.height = Math.round(video.videoHeight * scale)
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
  return canvas.toDataURL('image/jpeg', EVIDENCE_QUALITY)
}

/**
 * Records a relapse-risk incident. At `escalated` this is what the caregiver's
 * dashboard picks up in real time.
 */
export async function recordRelapseIncident(
  uid: string,
  stage: RelapseStage,
  observation: string,
  video: HTMLVideoElement | null,
): Promise<void> {
  const frame = captureFrame(video)
  await addDoc(collection(db, 'users', uid, 'incidents'), {
    stage,
    observation: observation.slice(0, 500),
    ...(frame ? { frame } : {}),
    createdAt: serverTimestamp(),
  })
}
