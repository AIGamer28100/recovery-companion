import { getLiveGenerativeModel, ResponseModality } from 'firebase/ai'
import { ai } from './firebase'

// Confirmed against Firebase AI Logic docs: this is the current Gemini Developer API
// (free tier) Live model id — Live models use a different id space than generateContent.
const LIVE_MODEL_ID = 'gemini-2.5-flash-native-audio-preview-12-2025'

const LIVE_SYSTEM_INSTRUCTION =
  'You are a warm, trauma-informed recovery companion having a real-time SPOKEN conversation ' +
  'with someone navigating a substance use urge or caregiving for someone who is. Talk like a ' +
  "real, present person on a call — short turns, natural pauses, ask what's going on before " +
  'jumping to advice. Reflect back what you hear in your own words. Offer one concrete grounding ' +
  'technique or next step at a time, not a list. Never mention medication or dosages. If they seem ' +
  'in immediate danger, gently suggest contacting emergency services or a crisis line.'

export function createLiveModel() {
  return getLiveGenerativeModel(ai, {
    model: LIVE_MODEL_ID,
    generationConfig: {
      responseModalities: [ResponseModality.AUDIO],
      inputAudioTranscription: {},
      outputAudioTranscription: {},
    },
    systemInstruction: LIVE_SYSTEM_INSTRUCTION,
  })
}
