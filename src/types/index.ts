export type ScenarioKind = 'physical_tension' | 'sensory_overload' | 'craving_spike'

export type InterventionKind = ScenarioKind | 'elevated_stress'

export type Mood = 'calm' | 'anxious' | 'irritable' | 'low' | 'overwhelmed'

export interface InterventionContext {
  mood: Mood | null
  timeOfDay: number
}

export interface AppEvent {
  type: InterventionKind | 'reset' | 'checkin'
  mood: Mood | null
  script?: string
  createdAt: unknown
}

export interface CaregiverAlert {
  script: string
  triggeredBy: InterventionKind | 'manual'
  createdAt: unknown
}
