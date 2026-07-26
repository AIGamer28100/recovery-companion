import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/domain/user_profile.dart';

/// The navigation shell's home screen. For a signed-in patient, this is
/// where the real M3 Live Call screen is reached from — a caregiver instead
/// only sees their status text, since the Live Call screen is patient-only.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider).valueOrNull;
    final profile = session?.profile;
    final name = profile?.displayName ?? session?.user?.email ?? 'there';
    final roleLabel = switch (profile?.role) {
      UserRole.patient => 'Signed in as the person in recovery',
      UserRole.caregiver => 'Signed in as a caregiver',
      null => 'Signed in',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Soter Recovery')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hi, $name', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  roleLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 40),
                if (profile?.role == UserRole.patient) ...[
                  FilledButton.icon(
                    onPressed: () => context.push('/live-call'),
                    icon: const Icon(Icons.mic),
                    label: const Text('Start a live call'),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton(
                  onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
