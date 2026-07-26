import { describe, it, expect, vi, afterEach } from 'vitest'
import { detectCameraAvailability, describeCameraForModel } from './cameraAvailability'

function stubNavigator(overrides: {
  mediaDevices?: {
    enumerateDevices?: ReturnType<typeof vi.fn>
    getUserMedia?: ReturnType<typeof vi.fn>
  }
  permissionsQuery?: ReturnType<typeof vi.fn>
}) {
  const mediaDevices = overrides.mediaDevices
    ? {
        enumerateDevices: overrides.mediaDevices.enumerateDevices,
        getUserMedia: overrides.mediaDevices.getUserMedia,
      }
    : undefined

  vi.stubGlobal('navigator', {
    mediaDevices,
    permissions: overrides.permissionsQuery ? { query: overrides.permissionsQuery } : undefined,
  })
}

describe('detectCameraAvailability', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('returns blocked/false when permission is denied, without touching getUserMedia', async () => {
    const getUserMedia = vi.fn()
    const enumerateDevices = vi.fn()
    stubNavigator({
      mediaDevices: { enumerateDevices, getUserMedia },
      permissionsQuery: vi.fn().mockResolvedValue({ state: 'denied' }),
    })
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'blocked', canOffer: false })
    expect(getUserMedia).not.toHaveBeenCalled()
  })

  it('returns available/true when a videoinput device is present', async () => {
    stubNavigator({
      mediaDevices: {
        enumerateDevices: vi.fn().mockResolvedValue([
          { kind: 'audioinput' },
          { kind: 'videoinput' },
        ]),
      },
      permissionsQuery: vi.fn().mockResolvedValue({ state: 'prompt' }),
    })
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'available', canOffer: true })
  })

  it('returns none/false when no videoinput device is present', async () => {
    stubNavigator({
      mediaDevices: {
        enumerateDevices: vi.fn().mockResolvedValue([{ kind: 'audioinput' }]),
      },
      permissionsQuery: vi.fn().mockResolvedValue({ state: 'prompt' }),
    })
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'none', canOffer: false })
  })

  it('returns unsupported/false when mediaDevices API is missing', async () => {
    stubNavigator({})
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'unsupported', canOffer: false })
  })

  it('returns unsupported when enumerateDevices throws', async () => {
    stubNavigator({
      mediaDevices: {
        enumerateDevices: vi.fn().mockRejectedValue(new Error('nope')),
      },
      permissionsQuery: vi.fn().mockResolvedValue({ state: 'prompt' }),
    })
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'unsupported', canOffer: false })
  })

  it('falls through to enumeration when permissions.query throws (Firefox/Safari)', async () => {
    stubNavigator({
      mediaDevices: {
        enumerateDevices: vi.fn().mockResolvedValue([{ kind: 'videoinput' }]),
      },
      permissionsQuery: vi.fn().mockRejectedValue(new Error('camera permission name unsupported')),
    })
    const result = await detectCameraAvailability()
    expect(result).toEqual({ state: 'available', canOffer: true })
  })
})

describe('describeCameraForModel', () => {
  it('gives distinct on-camera copy when isOn is true, regardless of state', () => {
    const copy = describeCameraForModel({ state: 'available', canOffer: true }, true)
    expect(copy).toContain('currently ON')
  })

  it('for available+off, invites turning the camera on', () => {
    const copy = describeCameraForModel({ state: 'available', canOffer: true }, false)
    expect(copy).toContain('camera IS available')
  })

  it('for blocked, explicitly instructs not to ask for the camera', () => {
    const copy = describeCameraForModel({ state: 'blocked', canOffer: false }, false)
    expect(copy).toContain('Do NOT ask them to turn the camera on')
  })

  it('for none, explicitly instructs never to ask for the camera', () => {
    const copy = describeCameraForModel({ state: 'none', canOffer: false }, false)
    expect(copy).toContain('Never ask them to turn on a camera')
  })

  it('for unsupported, explicitly instructs not to ask for the camera', () => {
    const copy = describeCameraForModel({ state: 'unsupported', canOffer: false }, false)
    expect(copy).toContain('Do not ask them to turn on a camera')
  })

  it('produces meaningfully different copy across blocked/none/unsupported/available', () => {
    const variants = [
      describeCameraForModel({ state: 'available', canOffer: true }, false),
      describeCameraForModel({ state: 'blocked', canOffer: false }, false),
      describeCameraForModel({ state: 'none', canOffer: false }, false),
      describeCameraForModel({ state: 'unsupported', canOffer: false }, false),
    ]
    expect(new Set(variants).size).toBe(variants.length)
  })
})
