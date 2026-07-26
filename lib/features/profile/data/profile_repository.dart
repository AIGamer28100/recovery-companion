import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/user_profile.dart';

/// The only place `cloud_firestore` may be imported from for the `users`
/// collection family. A faithful Dart port of `src/lib/profile.ts` — field
/// names, types, and the linking model (patient-initiated, keyed on the
/// caregiver's own verified auth email) must match exactly, or the web
/// caregiver dashboard silently breaks.
abstract class ProfileRepository {
  Future<UserProfile?> getProfile(String uid);

  Future<void> createPatientProfile({
    required String uid,
    required String email,
    required EmergencyContact emergencyContact,
    String? displayName,
    String? photoURL,
    String? caregiverEmail,
  });

  Future<void> createCaregiverProfile({
    required String uid,
    required String email,
    String? displayName,
    String? photoURL,
  });

  /// Finds the patient who nominated [caregiverEmail] as their caregiver.
  /// This is how a caregiver is recognised — never how a patient looks
  /// anyone up. Mirrors `findLinkedPatient` in `src/lib/profile.ts`.
  Future<String?> findLinkedPatientUid(String caregiverEmail);

  Future<void> updateEmergencyContact(String uid, EmergencyContact contact);

  /// A patient nominating a caregiver. Only the patient can call this.
  Future<void> nominateCaregiver(String uid, String caregiverEmail);
}

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<UserProfile?> getProfile(String uid) async {
    try {
      final snap = await _users.doc(uid).get();
      if (!snap.exists) return null;
      return _fromDoc(uid, snap.data()!);
    } on FirebaseException catch (e) {
      throw AppException(e.message ?? 'Could not load your profile.');
    }
  }

  @override
  Future<void> createPatientProfile({
    required String uid,
    required String email,
    required EmergencyContact emergencyContact,
    String? displayName,
    String? photoURL,
    String? caregiverEmail,
  }) async {
    final normalized = caregiverEmail?.trim().toLowerCase();
    try {
      await _users.doc(uid).set({
        'role': UserRole.patient.wireValue,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'emergencyContact': emergencyContact.toMap(),
        'linkedCaregiverEmails':
            (normalized != null && normalized.isNotEmpty) ? [normalized] : <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AppException(
        e.message ?? 'Could not save that. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> createCaregiverProfile({
    required String uid,
    required String email,
    String? displayName,
    String? photoURL,
  }) async {
    try {
      // Deliberately no `emergencyContact`/`linkedCaregiverEmails` keys —
      // those are patient-only fields, matching `createCaregiverProfile` in
      // src/lib/profile.ts exactly.
      await _users.doc(uid).set({
        'role': UserRole.caregiver.wireValue,
        'email': email,
        'displayName': displayName,
        'photoURL': photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw AppException(
        e.message ?? 'Could not save that. Check your connection and try again.',
      );
    }
  }

  @override
  Future<String?> findLinkedPatientUid(String caregiverEmail) async {
    final normalized = caregiverEmail.trim().toLowerCase();
    try {
      final snap = await _users
          .where('linkedCaregiverEmails', arrayContains: normalized)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } on FirebaseException catch (e) {
      throw AppException(e.message ?? 'Could not check that right now.');
    }
  }

  @override
  Future<void> updateEmergencyContact(String uid, EmergencyContact contact) async {
    try {
      await _users.doc(uid).update({'emergencyContact': contact.toMap()});
    } on FirebaseException catch (e) {
      throw AppException(e.message ?? 'Could not save that. Try again.');
    }
  }

  @override
  Future<void> nominateCaregiver(String uid, String caregiverEmail) async {
    final normalized = caregiverEmail.trim().toLowerCase();
    try {
      await _users.doc(uid).update({
        'linkedCaregiverEmails': FieldValue.arrayUnion([normalized]),
      });
    } on FirebaseException catch (e) {
      throw AppException(e.message ?? 'Could not save that. Try again.');
    }
  }

  UserProfile _fromDoc(String uid, Map<String, dynamic> data) {
    final rawContact = data['emergencyContact'];
    final rawEmails = data['linkedCaregiverEmails'] as List<dynamic>?;
    final createdAt = data['createdAt'];
    return UserProfile(
      uid: uid,
      role: UserRole.fromWireValue(data['role'] as String),
      email: data['email'] as String,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      emergencyContact: rawContact is Map
          ? EmergencyContact.fromMap(Map<String, dynamic>.from(rawContact))
          : null,
      linkedCaregiverEmails:
          rawEmails?.map((e) => e as String).toList() ?? const <String>[],
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return FirestoreProfileRepository();
});

/// The signed-in user's profile doc, keyed by uid so it can be invalidated
/// (and safely re-fetched per-user) right after onboarding writes it.
final profileProvider =
    FutureProvider.family<UserProfile?, String>((ref, uid) {
  return ref.watch(profileRepositoryProvider).getProfile(uid);
});
