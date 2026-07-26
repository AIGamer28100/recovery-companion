import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../application/onboarding_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _caregiverEmailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _caregiverEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final signedInEmail = ref.watch(authStateChangesProvider).value?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  switch (state.step) {
                    OnboardingStep.chooseRole => _ChooseRole(
                        busy: state.isSubmitting,
                        onPatient: controller.chooseRoleGoToPatientDetails,
                        onCaregiver: controller.chooseCaregiverRole,
                      ),
                    OnboardingStep.patientDetails => _PatientDetails(
                        busy: state.isSubmitting,
                        nameController: _nameController,
                        phoneController: _phoneController,
                        caregiverEmailController: _caregiverEmailController,
                        onSubmit: () => controller.submitPatient(
                          contactName: _nameController.text.trim(),
                          contactPhone: _phoneController.text.trim(),
                          caregiverEmail: _caregiverEmailController.text.trim().isEmpty
                              ? null
                              : _caregiverEmailController.text.trim(),
                        ),
                      ),
                    OnboardingStep.caregiverNotFound => _CaregiverNotFound(
                        email: signedInEmail,
                        onBack: controller.backToChoice,
                      ),
                  },
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      state.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChooseRole extends StatelessWidget {
  const _ChooseRole({required this.busy, required this.onPatient, required this.onCaregiver});

  final bool busy;
  final VoidCallback onPatient;
  final VoidCallback onCaregiver;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Who's using this?",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          "This helps us tailor what you see. You can't change this later in this build.",
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: busy ? null : onPatient,
          child: const Text("I'm the person in recovery"),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : onCaregiver,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("I'm a caregiver"),
        ),
      ],
    );
  }
}

class _PatientDetails extends StatelessWidget {
  const _PatientDetails({
    required this.busy,
    required this.nameController,
    required this.phoneController,
    required this.caregiverEmailController,
    required this.onSubmit,
  });

  final bool busy;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController caregiverEmailController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([nameController, phoneController]),
      builder: (context, _) {
        final canSubmit =
            !busy && nameController.text.trim().isNotEmpty && phoneController.text.trim().isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Who should we reach?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              "Add one person you'd want called on a hard night. They'll be one tap "
              "away inside the app, and if you nominate them by email, they'll be "
              "able to sign in as your caregiver.",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: "Their name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: "Their phone number"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: caregiverEmailController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: "Their Google email (optional)"),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: canSubmit ? onSubmit : null,
              child: Text(busy ? 'Saving…' : 'Save and continue'),
            ),
            const SizedBox(height: 12),
            Text(
              "A contact is required — on a hard night you shouldn't have to go "
              "looking for a number. Add their Google email too and they can sign "
              "in as your caregiver to see your patterns and get alerts. Only you "
              "can grant that, and only to an address you enter here.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}

class _CaregiverNotFound extends StatelessWidget {
  const _CaregiverNotFound({required this.email, required this.onBack});

  final String email;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No invitation yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              children: [
                const TextSpan(
                  text: "Nobody has added this email as their caregiver yet. For "
                      "their privacy, only the person in recovery can grant that — "
                      "ask them to add ",
                ),
                TextSpan(
                  text: email,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
                const TextSpan(text: ' in their app, then sign in again.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}
