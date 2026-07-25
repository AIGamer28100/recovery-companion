import { getGenerativeModel } from 'firebase/ai'
import { ai } from './firebase'
import type { InterventionContext, InterventionKind } from '../types'

const MODEL_ID = 'gemini-2.5-flash'

const SYSTEM_INSTRUCTIONS: Record<InterventionKind, string> = {
  physical_tension:
    'You are a calm, trauma-informed recovery companion for someone in physical tension ' +
    '(clenched jaw, tight chest, restlessness) related to a substance use urge. In under 80 words, ' +
    'give one concrete grounding technique they can do right now with their body, then one small next ' +
    'action. Plain, warm, zero jargon. Never mention medication or dosages.',
  sensory_overload:
    'You are a calm, trauma-informed recovery companion for someone experiencing sensory overload ' +
    '(too much noise/light/stimulation) that is triggering a craving. In under 80 words, give one concrete ' +
    'way to reduce sensory input right now, then one small next action. Plain, warm, zero jargon.',
  craving_spike:
    'You are a calm, trauma-informed recovery companion for someone in a sudden, intense craving spike. ' +
    'In under 80 words, give a "surf the urge" style script: name that cravings peak and pass, one delay-and-distract ' +
    'action for the next 10 minutes, and one concrete next step (e.g. call a support contact). Plain, warm, zero jargon.',
  elevated_stress:
    'You are a calm, trauma-informed recovery companion. The person has shown signs of rising stress ' +
    '(rapid app interaction or a long unresponsive period during a known high-risk time). Proactively, in under ' +
    '80 words, check in on them, offer one grounding action, and one small next step. Plain, warm, non-alarming.',
}

function buildPrompt(context: InterventionContext): string {
  const timeContext =
    context.timeOfDay >= 21 || context.timeOfDay <= 4
      ? 'It is late at night, a known higher-risk time.'
      : 'It is daytime.'
  const moodContext = context.mood ? `They just indicated they feel: ${context.mood}.` : ''
  return `${timeContext} ${moodContext}`.trim()
}

export async function generateIntervention(
  kind: InterventionKind,
  context: InterventionContext,
): Promise<string> {
  const model = getGenerativeModel(ai, {
    model: MODEL_ID,
    systemInstruction: SYSTEM_INSTRUCTIONS[kind],
    generationConfig: { maxOutputTokens: 300, temperature: 0.8 },
  })
  const result = await model.generateContent(buildPrompt(context))
  return result.response.text()
}

export async function generateCaregiverScript(
  kind: InterventionKind,
  context: InterventionContext,
): Promise<string> {
  const model = getGenerativeModel(ai, {
    model: MODEL_ID,
    systemInstruction:
      'You are drafting a short message FOR A CAREGIVER (not the person in recovery) who just received an ' +
      'alert about their person. In under 60 words, plainly state what happened and suggest one supportive, ' +
      'non-judgmental thing the caregiver could say or do right now. Never suggest confrontation or ultimatums.',
    generationConfig: { maxOutputTokens: 200, temperature: 0.7 },
  })
  const result = await model.generateContent(
    `Alert type: ${kind}. ${buildPrompt(context)}`,
  )
  return result.response.text()
}
