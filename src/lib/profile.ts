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

export interface GoogleIdentity {
  displayName: string | null
  photoURL: string | null
}

export async function getUserProfile(uid: string): Promise<UserProfile | null> {
  const snap = await getDoc(doc(db, 'users', uid))
  return snap.exists() ? (snap.data() as UserProfile) : null
}

export async function createPatientProfile(
  uid: string,
  email: string,
  emergencyContact: { name: string; phone: string },
  identity: GoogleIdentity,
  caregiverEmail?: string,
): Promise<void> {
  const caregiverEmails = caregiverEmail?.trim()
    ? [caregiverEmail.trim().toLowerCase()]
    : []
  await setDoc(doc(db, 'users', uid), {
    role: 'patient',
    email,
    displayName: identity.displayName,
    photoURL: identity.photoURL,
    emergencyContact,
    linkedCaregiverEmails: caregiverEmails,
    createdAt: serverTimestamp(),
  })
}

export async function createCaregiverProfile(
  uid: string,
  email: string,
  identity: GoogleIdentity,
): Promise<void> {
  await setDoc(doc(db, 'users', uid), {
    role: 'caregiver',
    email,
    displayName: identity.displayName,
    photoURL: identity.photoURL,
    createdAt: serverTimestamp(),
  })
}

/**
 * Finds the patient who nominated this caregiver.
 *
 * Security rules evaluate `allow read` per document, so this constrained query
 * returns only patients that actually listed this email. An unconstrained listing
 * of /users is denied outright — which is what prevents user enumeration.
 */
export async function findLinkedPatient(caregiverEmail: string): Promise<string | null> {
  const snap = await getDocs(
    query(
      collection(db, 'users'),
      where('linkedCaregiverEmails', 'array-contains', caregiverEmail.trim().toLowerCase()),
      limit(1),
    ),
  )
  return snap.docs[0]?.id ?? null
}

/** Lets someone correct their emergency contact later. */
export async function updateEmergencyContact(
  uid: string,
  emergencyContact: { name: string; phone: string },
): Promise<void> {
  await updateDoc(doc(db, 'users', uid), { emergencyContact })
}

/** A patient nominating a caregiver. Only the patient can do this. */
export async function nominateCaregiver(uid: string, caregiverEmail: string): Promise<void> {
  await updateDoc(doc(db, 'users', uid), {
    linkedCaregiverEmails: arrayUnion(caregiverEmail.trim().toLowerCase()),
  })
}
