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

export async function createPatientProfile(
  uid: string,
  email: string,
  emergencyContact: { name: string; phone: string } | null = null,
): Promise<void> {
  await setDoc(doc(db, 'users', uid), {
    role: 'patient',
    email,
    linkedCaregiverUids: [],
    emergencyContact,
    createdAt: serverTimestamp(),
  })
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
): Promise<{ linked: boolean }> {
  const match = await findPatientByEmail(patientEmail.trim().toLowerCase())

  await setDoc(doc(db, 'users', uid), {
    role: 'caregiver',
    email,
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
