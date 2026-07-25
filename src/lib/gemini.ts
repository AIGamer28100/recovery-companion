import { getGenerativeModel } from 'firebase/ai'
import { ai } from './firebase'
import type { InterventionContext, InterventionKind } from '../types'

const MODEL_ID = 'gemini-flash-latest'

// gemini-flash-latest budgets extended reasoning out of maxOutputTokens by default,
// which was silently truncating short replies mid-sentence (thinkingBudget: 0 isn't
// accepted by this model, so the fix is just a generous ceiling instead).
const RESPONSE_CONFIG = {
  maxOutputTokens: 2048,
  temperature: 1.0,
  topP: 0.95,
}

const SCENARIO_DESCRIPTIONS: Record<string, string> = {
  physical_tension: 'a tight chest, clenched jaw, and physical restlessness building up',
  sensory_overload: 'too much noise, light, or stimulation around them right now, which is triggering a craving',
  craving_spike: 'a sudden, intense craving that just hit hard',
  elevated_stress:
    "signs of rising stress — either tapping the app rapidly or going quiet for a long stretch during a time that's historically higher-risk for them",
}

const SYSTEM_INSTRUCTIONS: Record<InterventionKind, string> = {
  physical_tension:
    'You are a warm, trauma-informed recovery companion talking directly to someone right now, in the moment, ' +
    'as they navigate a substance use urge. You are not a script generator — respond like a real person who is ' +
    "paying attention to exactly what they just told you. Open by briefly naming what's happening for them in " +
    "your own words (don't just repeat their input back verbatim), then walk them through ONE specific, physical " +
    "grounding technique they can do in the next 30 seconds, then suggest one small concrete next step. Vary your " +
    'wording and approach each time — never fall back on a stock opening line. 4-7 short sentences. Plain language, ' +
    'no clinical jargon, never mention medication or dosages.',
  sensory_overload:
    'You are a warm, trauma-informed recovery companion talking directly to someone right now who is overwhelmed ' +
    'by their environment and feels a craving building because of it. Respond like a real person reacting to their ' +
    "specific situation, not a canned script. Briefly acknowledge what's happening, then give ONE concrete way to " +
    'reduce sensory input immediately, then one small next step. Vary your wording each time. 4-7 short sentences, ' +
    'plain language, no jargon.',
  craving_spike:
    'You are a warm, trauma-informed recovery companion talking directly to someone in the middle of a sudden, ' +
    'intense craving spike. Respond like a real person, not a template. Briefly name what they\'re going through, ' +
    'remind them cravings peak and pass (usually within 10-20 minutes), give ONE specific delay-and-distract action ' +
    'for right now, and one concrete next step (like reaching out to a support contact). Vary your wording and ' +
    'examples each time. 4-7 short sentences, plain language, no jargon.',
  elevated_stress:
    'You are a warm, trauma-informed recovery companion. You are proactively checking in because the app noticed ' +
    "signs of rising stress. Respond like a real person checking in on someone they care about, not a script. " +
    "Gently name what you noticed, ask how they're doing without being alarming, offer ONE grounding action, and " +
    'one small next step. Vary your wording each time. 4-7 short sentences, plain, warm, non-alarming.',
}

function buildPrompt(kind: InterventionKind, context: InterventionContext): string {
  const timeContext =
    context.timeOfDay >= 21 || context.timeOfDay <= 4
      ? 'It is late at night right now, which is historically a higher-risk time for them.'
      : 'It is daytime right now.'
  const moodContext = context.mood
    ? `They just tapped that they're feeling: ${context.mood}.`
    : "They haven't shared a specific mood."
  const situation = SCENARIO_DESCRIPTIONS[kind] ?? kind
  return (
    `Right now, this person is experiencing: ${situation}. ${timeContext} ${moodContext} ` +
    'Respond directly to them as if you are with them in this exact moment.'
  ).trim()
}

export async function generateIntervention(
  kind: InterventionKind,
  context: InterventionContext,
): Promise<string> {
  const model = getGenerativeModel(ai, {
    model: MODEL_ID,
    systemInstruction: SYSTEM_INSTRUCTIONS[kind],
    generationConfig: RESPONSE_CONFIG,
  })
  const result = await model.generateContent(buildPrompt(kind, context))
  return result.response.text()
}

export async function generateCaregiverScript(
  kind: InterventionKind,
  context: InterventionContext,
): Promise<string> {
  const model = getGenerativeModel(ai, {
    model: MODEL_ID,
    systemInstruction:
      'You are drafting a short, warm message FOR A CAREGIVER (not the person in recovery) who just received an ' +
      "alert about their person. Respond naturally to the specific situation described, not with a generic template. " +
      'Plainly state what happened, then suggest one supportive, non-judgmental thing the caregiver could say or do ' +
      'right now. Never suggest confrontation or ultimatums. 3-5 short sentences.',
    generationConfig: RESPONSE_CONFIG,
  })
  const result = await model.generateContent(
    `Alert reason: ${kind}. ${buildPrompt(kind, context)}`,
  )
  return result.response.text()
}
