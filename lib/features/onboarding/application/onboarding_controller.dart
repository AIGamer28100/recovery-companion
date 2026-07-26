import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/user_profile.dart';

enum OnboardingStep { chooseRole, patientDetails, caregiverNotFound }

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.chooseRole,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final OnboardingStep step;
  final bool isSubmitting;
  final String? errorMessage;

  OnboardingState copyWith({
    OnboardingStep? step,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives the role-choice / patient-details / caregiver-lookup flow.
/// Mirrors `RoleOnboarding.tsx`'s state machine faithfully: patient path
/// requires a name+phone emergency contact and offers an optional caregiver
/// email nomination; caregiver path does no typing at all — it resolves who
/// nominated the signed-in Google account via `findLinkedPatient`.
class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void chooseRoleGoToPatientDetails() {
    state = state.copyWith(step: OnboardingStep.patientDetails, clearError: true);
  }

  void backToChoice() {
    state = state.copyWith(step: OnboardingStep.chooseRole, clearError: true);
  }

  Future<void> submitPatient({
    required String contactName,
    required String contactPhone,
    String? caregiverEmail,
  }) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await ref.read(profileRepositoryProvider).createPatientProfile(
            uid: user.uid,
            email: user.email,
            emergencyContact: EmergencyContact(name: contactName, phone: contactPhone),
            displayName: user.displayName,
            photoURL: user.photoUrl,
            caregiverEmail: caregiverEmail,
          );
      ref.invalidate(profileProvider(user.uid));
      state = state.copyWith(isSubmitting: false);
    } on AppException catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: "Couldn't save that. Check your connection and try again.",
      );
    }
  }

  Future<void> chooseCaregiverRole() async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final patientUid =
          await ref.read(profileRepositoryProvider).findLinkedPatientUid(user.email);
      if (patientUid == null) {
        state = state.copyWith(
          isSubmitting: false,
          step: OnboardingStep.caregiverNotFound,
        );
        return;
      }
      await ref.read(profileRepositoryProvider).createCaregiverProfile(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            photoURL: user.photoUrl,
          );
      ref.invalidate(profileProvider(user.uid));
      state = state.copyWith(isSubmitting: false);
    } on AppException catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: "Couldn't check that right now. Try again.",
      );
    }
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(OnboardingController.new);
