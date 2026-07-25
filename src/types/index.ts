export type ScenarioKind = 'physical_tension' | 'sensory_overload' | 'craving_spike'

export type InterventionKind = ScenarioKind | 'elevated_stress'

export type Mood = 'calm' | 'anxious' | 'irritable' | 'low' | 'overwhelmed'

export type UserRole = 'patient' | 'caregiver'

export interface InterventionContext {
  mood: Mood | null
  timeOfDay: number
}

export interface AppEvent {
  type: InterventionKind | 'reset' | 'checkin' | 'live_conversation'
  mood: Mood | null
  script?: string
  createdAt: unknown
}

export interface CaregiverAlert {
  script: string
  triggeredBy: InterventionKind | 'manual' | 'relapse_risk'
  createdAt: unknown
}

export interface UserProfile {
  role: UserRole
  email: string
  /** From the Google account used to sign in. */
  displayName?: string | null
  photoURL?: string | null
  /**
   * Patients only. Someone they can call themselves when there's no linked
   * caregiver receiving alerts. Null means they're relying on public helplines.
   */
  emergencyContact?: { name: string; phone: string } | null
  // Patients: uids of caregivers who may read their events/alerts.
  linkedCaregiverUids?: string[]
  // Caregivers: the single patient they're linked to, if any.
  linkedPatientUid?: string | null
  createdAt: unknown
}
