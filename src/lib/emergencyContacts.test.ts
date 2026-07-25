import { describe, it, expect } from 'vitest'
import { toTelHref, describeSupportForModel, PUBLIC_HELPLINES } from './emergencyContacts'

describe('toTelHref', () => {
  it('strips spaces and punctuation but keeps a leading +', () => {
    expect(toTelHref('+91 98765-43210')).toBe('tel:+919876543210')
  })

  it('strips punctuation from a domestic-style number with no plus', () => {
    expect(toTelHref('1800-599-0019')).toBe('tel:18005990019')
  })

  it('strips parentheses and dots', () => {
    expect(toTelHref('(044) 123.456')).toBe('tel:044123456')
  })
})

describe('describeSupportForModel', () => {
  it('describes the linked-caregiver branch distinctly', () => {
    const copy = describeSupportForModel(null, true)
    expect(copy).toContain('caregiver linked to this account')
  })

  it('describes the contact-only branch distinctly, naming the contact', () => {
    const copy = describeSupportForModel({ name: 'Asha', phone: '9876543210' }, false)
    expect(copy).toContain('Asha')
    expect(copy).toContain('NO caregiver linked')
  })

  it('describes the neither branch and warns against telling them to generically "call someone"', () => {
    const copy = describeSupportForModel(null, false)
    expect(copy).toContain('NO caregiver and NO emergency contact')
    expect(copy).toContain('call someone')
  })

  it('produces three distinct branches', () => {
    const branches = [
      describeSupportForModel(null, true),
      describeSupportForModel({ name: 'Asha', phone: '123' }, false),
      describeSupportForModel(null, false),
    ]
    expect(new Set(branches).size).toBe(3)
  })
})

describe('PUBLIC_HELPLINES', () => {
  it('is non-empty', () => {
    expect(PUBLIC_HELPLINES.length).toBeGreaterThan(0)
  })

  it('every entry has a name, phone, and detail', () => {
    for (const helpline of PUBLIC_HELPLINES) {
      expect(helpline.name).toBeTruthy()
      expect(helpline.phone).toBeTruthy()
      expect(helpline.detail).toBeTruthy()
    }
  })
})
