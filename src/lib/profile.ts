import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  arrayUnion,
  collection,
  query,
  where,
  limit,
  getDocs,
  serverTimestamp,
} from 'firebase/firestore'
import { db } from './firebase'
import type { UserProfile } from '../types'

export async function getUserProfile(uid: string): Promise<UserProfile | null> {
  const snap = await getDoc(doc(db, 'users', uid))
  return snap.exists() ? (snap.data() as UserProfile) : null
}

export interface GoogleIdentity {
  displayName: string | null
  photoURL: string | null
}

export async function createPatientProfile(
  uid: string,
  email: string,
  emergencyContact: { name: string; phone: string },
  identity: GoogleIdentity,
): Promise<void> {
  await setDoc(doc(db, 'users', uid), {
    role: 'patient',
    email,
    displayName: identity.displayName,
    photoURL: identity.photoURL,
    linkedCaregiverUids: [],
    emergencyContact,
    createdAt: serverTimestamp(),
  })
}

/** Lets someone correct their emergency contact later from Settings. */
export async function updateEmergencyContact(
  uid: string,
  emergencyContact: { name: string; phone: string },
): Promise<void> {
  await updateDoc(doc(db, 'users', uid), { emergencyContact })
}

interface PatientMatch {
  uid: string
  profile: UserProfile
}

async function findPatientByEmail(email: string): Promise<PatientMatch | null> {
  const q = query(collection(db, 'users'), where('email', '==', email), limit(5))
  const snap = await getDocs(q)
  for (const d of snap.docs) {
    const data = d.data() as UserProfile
    if (data.role === 'patient') return { uid: d.id, profile: data }
  }
  return null
}

export async function createCaregiverProfileAndLink(
  uid: string,
  email: string,
  patientEmail: string,
  identity: GoogleIdentity,
): Promise<{ linked: boolean }> {
  const match = await findPatientByEmail(patientEmail.trim().toLowerCase())

  await setDoc(doc(db, 'users', uid), {
    role: 'caregiver',
    email,
    displayName: identity.displayName,
    photoURL: identity.photoURL,
    linkedPatientUid: match?.uid ?? null,
    createdAt: serverTimestamp(),
  })

  if (match) {
    await updateDoc(doc(db, 'users', match.uid), {
      linkedCaregiverUids: arrayUnion(uid),
    })
  }

  return { linked: match !== null }
}
