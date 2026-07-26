// Deliberately slower and slightly lower than browser defaults: this text is read
// to someone mid-craving or mid-panic, where a brisk default TTS pace reads as
// urgent and adds pressure rather than settling them.
const RATE = 0.82
const PITCH = 0.95

function pickCalmVoice(): SpeechSynthesisVoice | null {
  const voices = window.speechSynthesis.getVoices()
  if (voices.length === 0) return null
  // Prefer a natural/neural English voice when the platform offers one.
  return (
    voices.find((v) => /en/i.test(v.lang) && /natural|neural|google/i.test(v.name)) ??
    voices.find((v) => /^en[-_]/i.test(v.lang)) ??
    null
  )
}

export function speak(text: string): void {
  if (!('speechSynthesis' in window)) return
  try {
    window.speechSynthesis.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.rate = RATE
    utterance.pitch = PITCH
    const voice = pickCalmVoice()
    if (voice) utterance.voice = voice
    window.speechSynthesis.speak(utterance)
  } catch (err) {
    console.warn('Speech synthesis unavailable', err)
  }
}

export function stopSpeaking(): void {
  if (!('speechSynthesis' in window)) return
  try {
    window.speechSynthesis.cancel()
  } catch {
    // nothing playing
  }
}
