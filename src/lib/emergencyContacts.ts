export interface EmergencyContact {
  name: string
  phone: string
}

export interface Helpline {
  name: string
  phone: string
  detail: string
}

/**
 * Fallback support for someone with nobody linked.
 *
 * These are India-wide government helplines, since this build targets users in
 * India. Before deploying anywhere else — or to real users anywhere — these MUST
 * be re-verified and localised: a stale crisis number is actively dangerous.
 */
export const PUBLIC_HELPLINES: Helpline[] = [
  {
    name: 'Tele-MANAS',
    phone: '14416',
    detail: "India's 24/7 national mental health support line",
  },
  {
    name: 'KIRAN',
    phone: '1800-599-0019',
    detail: '24/7 national mental health rehabilitation helpline',
  },
  {
    name: 'Emergency services',
    phone: '112',
    detail: 'If you or someone else is in immediate danger',
  },
]

/** `tel:` links need the punctuation stripped. */
export function toTelHref(phone: string): string {
  return `tel:${phone.replace(/[^\d+]/g, '')}`
}

/**
 * The line handed to the model so it knows who this person can actually reach,
 * and never tells them to "call someone" when there is nobody to call.
 */
export function describeSupportForModel(
  contact: EmergencyContact | null,
  hasLinkedCaregiver: boolean,
): string {
  if (hasLinkedCaregiver) {
    return (
      'They have a caregiver linked to this account who receives alerts. You may encourage them ' +
      'to reach out to that person when it would help.'
    )
  }
  if (contact) {
    return (
      `They have NO caregiver linked, but they nominated an emergency contact: ${contact.name} ` +
      `(${contact.phone}). There is a button on their screen to call that person. Nobody is alerted ` +
      'automatically, so YOU are their first line of support — stay with them, and if things get ' +
      `serious, encourage them to tap that button and call ${contact.name}.`
    )
  }
  return (
    'They have NO caregiver and NO emergency contact — nobody is being alerted, and there is no ' +
    'person for them to call. YOU are their only support in this moment, so stay with them and do ' +
    'not hand them off. If they are in real danger, point them to the public helpline button on ' +
    'their screen (Tele-MANAS 14416, or 112 for emergencies in India). Never tell them to "call ' +
    'someone" generically — they may have no one, and that lands badly.'
  )
}
