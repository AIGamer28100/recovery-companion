import { addDoc, collection, serverTimestamp } from 'firebase/firestore'
import { db } from './firebase'
import type { AppEvent, CaregiverAlert } from '../types'

export function logEvent(uid: string, event: Omit<AppEvent, 'createdAt'>): void {
  addDoc(collection(db, 'users', uid, 'events'), {
    ...event,
    createdAt: serverTimestamp(),
  }).catch((err) => console.error('Failed to log event', err))
}

export function logCaregiverAlert(uid: string, alert: Omit<CaregiverAlert, 'createdAt'>): void {
  addDoc(collection(db, 'users', uid, 'alerts'), {
    ...alert,
    createdAt: serverTimestamp(),
  }).catch((err) => console.error('Failed to log caregiver alert', err))
}
