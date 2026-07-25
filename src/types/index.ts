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
  triggeredBy: InterventionKind | 'manual'
  createdAt: unknown
}

export interface UserProfile {
  role: UserRole
  email: string
  // Patients: uids of caregivers who may read their events/alerts.
  linkedCaregiverUids?: string[]
  // Caregivers: the single patient they're linked to, if any.
  linkedPatientUid?: string | null
  createdAt: unknown
}
