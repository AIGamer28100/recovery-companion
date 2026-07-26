export type CameraState =
  /** Hardware present and either already granted or still promptable. */
  | 'available'
  /** Hardware present but the user has explicitly blocked camera access. */
  | 'blocked'
  /** No camera hardware on this device. */
  | 'none'
  /** No media APIs, or not a secure context. */
  | 'unsupported'

export interface CameraAvailability {
  state: CameraState
  /** True only when it's actually worth offering the camera to the user. */
  canOffer: boolean
}

/**
 * Works out whether a camera is genuinely usable BEFORE the companion offers it.
 *
 * Asking someone to "turn on your camera" when they have no webcam, or have
 * already blocked the permission, is worse than not asking — it makes the
 * companion look like it isn't paying attention at exactly the moment they need
 * it to be.
 *
 * Deliberately does not call `getUserMedia`, which would trigger the permission
 * prompt as a side effect of merely checking.
 */
export async function detectCameraAvailability(): Promise<CameraAvailability> {
  if (typeof navigator === 'undefined' || !navigator.mediaDevices?.enumerateDevices) {
    return { state: 'unsupported', canOffer: false }
  }

  // A denied permission is decisive, so check it first where it's supported.
  // Firefox and Safari may not implement the 'camera' permission name at all.
  try {
    const status = await navigator.permissions?.query({
      name: 'camera' as PermissionName,
    })
    if (status?.state === 'denied') return { state: 'blocked', canOffer: false }
  } catch {
    // Permissions API unavailable for 'camera' — fall through to enumeration.
  }

  try {
    const devices = await navigator.mediaDevices.enumerateDevices()
    const hasCamera = devices.some((d) => d.kind === 'videoinput')
    return hasCamera ? { state: 'available', canOffer: true } : { state: 'none', canOffer: false }
  } catch {
    return { state: 'unsupported', canOffer: false }
  }
}

/** The line handed to the model so it knows whether offering the camera makes sense. */
export function describeCameraForModel(availability: CameraAvailability, isOn: boolean): string {
  if (isOn) {
    return 'Their camera is currently ON — you can see them. Use it to coach and validate what they do.'
  }
  switch (availability.state) {
    case 'available':
      return (
        'Their camera is currently OFF, but a working camera IS available and there is a camera ' +
        'button on their screen. If you want to coach them through something physical, ask them ' +
        'once to turn it on and say why it helps.'
      )
    case 'blocked':
      return (
        'They have BLOCKED camera access in their browser. Do NOT ask them to turn the camera on — ' +
        'you cannot see them and asking would only frustrate them. Coach entirely by voice.'
      )
    case 'none':
      return (
        'This device has NO camera at all. Never ask them to turn on a camera or to show you ' +
        'anything. Coach entirely by voice, and rely on what you hear and what they tell you.'
      )
    default:
      return (
        'Camera availability is unknown on this device. Do not ask them to turn on a camera. ' +
        'Coach entirely by voice.'
      )
  }
}
