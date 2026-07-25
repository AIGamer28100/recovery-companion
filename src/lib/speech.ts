export function speak(text: string): void {
  if (!('speechSynthesis' in window)) return
  try {
    window.speechSynthesis.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    window.speechSynthesis.speak(utterance)
  } catch (err) {
    console.warn('Speech synthesis unavailable', err)
  }
}
