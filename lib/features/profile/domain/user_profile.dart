// Plain-Dart models for the `users/{uid}` profile document. Field names and
// shapes here must match `firestore.rules` and the web app's
// `src/lib/profile.ts` exactly — this schema is shared with the caregiver
// web dashboard.

enum UserRole {
  patient,
  caregiver;

  /// The exact string stored in Firestore's `role` field.
  String get wireValue => switch (this) {
        UserRole.patient => 'patient',
        UserRole.caregiver => 'caregiver',
      };

  static UserRole fromWireValue(String value) => switch (value) {
        'patient' => UserRole.patient,
        'caregiver' => UserRole.caregiver,
        _ => throw ArgumentError('Unknown role: $value'),
      };
}

/// Matches `emergencyContact: {name: string, phone: string} | null`.
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;
  final String phone;

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: map['name'] as String,
      phone: map['phone'] as String,
    );
  }
}

/// Matches the `users/{uid}` document exactly:
/// `role`, `email`, `displayName`, `photoURL`, `emergencyContact`,
/// `linkedCaregiverEmails`, `createdAt`.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.role,
    required this.email,
    this.displayName,
    this.photoURL,
    this.emergencyContact,
    this.linkedCaregiverEmails = const [],
    this.createdAt,
  });

  final String uid;
  final UserRole role;
  final String email;
  final String? displayName;
  final String? photoURL;
  final EmergencyContact? emergencyContact;
  final List<String> linkedCaregiverEmails;
  final DateTime? createdAt;
}
