import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/live_session/presentation/live_call_screen.dart';
import '../../features/live_session/presentation/live_session_debug_harness_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/domain/user_profile.dart';

enum AppSessionStatus { signedOut, needsOnboarding, ready }

class AppSession {
  const AppSession(this.status, {this.user, this.profile});

  final AppSessionStatus status;
  final AppUser? user;
  final UserProfile? profile;
}

/// The single source of truth for "where should this user be in the app,"
/// combining Firebase Auth state with profile-doc existence. `go_router`'s
/// `redirect` reads this — not scattered per-screen checks.
final appSessionProvider = Provider<AsyncValue<AppSession>>((ref) {
  final authAsync = ref.watch(authStateChangesProvider);
  return authAsync.when(
    loading: () => const AsyncLoading(),
    error: (err, st) => AsyncError(err, st),
    data: (user) {
      if (user == null) {
        return const AsyncData(AppSession(AppSessionStatus.signedOut));
      }
      final profileAsync = ref.watch(profileProvider(user.uid));
      return profileAsync.when(
        loading: () => const AsyncLoading(),
        error: (err, st) => AsyncError(err, st),
        data: (profile) => AsyncData(
          profile == null
              ? AppSession(AppSessionStatus.needsOnboarding, user: user)
              : AppSession(AppSessionStatus.ready, user: user, profile: profile),
        ),
      );
    },
  );
});

/// Bridges Riverpod's `appSessionProvider` to `go_router`'s
/// `refreshListenable`, so a change in auth/profile state re-runs `redirect`.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<AppSession>>(appSessionProvider, (_, _) {
      notifyListeners();
    });
  }
}

const _splashPath = '/';
const _signInPath = '/sign-in';
const _onboardingPath = '/onboarding';
const _homePath = '/home';
const _liveCallPath = '/live-call';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: _splashPath,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(appSessionProvider);
      final location = state.matchedLocation;

      return session.when(
        loading: () => location == _splashPath ? null : _splashPath,
        error: (_, _) => location == _signInPath ? null : _signInPath,
        data: (s) {
          switch (s.status) {
            case AppSessionStatus.signedOut:
              return location == _signInPath ? null : _signInPath;
            case AppSessionStatus.needsOnboarding:
              return location == _onboardingPath ? null : _onboardingPath;
            case AppSessionStatus.ready:
              final onAuthScreen =
                  location == _signInPath || location == _onboardingPath || location == _splashPath;
              return onAuthScreen ? _homePath : null;
          }
        },
      );
    },
    routes: [
      GoRoute(path: _splashPath, builder: (context, state) => const SplashScreen()),
      GoRoute(path: _signInPath, builder: (context, state) => const SignInScreen()),
      GoRoute(path: _onboardingPath, builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: _homePath, builder: (context, state) => const HomeScreen()),
      // The real M3 Live Call screen (DESIGN.md §1.3) — reachable from
      // `HomeScreen` for a signed-in patient. Not route-guarded by role here
      // (a caregiver has no reason to navigate to it from the UI, and the
      // underlying session/tool-call plumbing is role-agnostic), matching
      // how every other screen besides the splash/auth flow is guarded only
      // by `AppSessionStatus`.
      GoRoute(path: _liveCallPath, builder: (context, state) => const LiveCallScreen()),
      // Scratch harness for manually exercising the M2 audio pipeline
      // (mic -> Live session -> playback, barge-in, focus handling) —
      // deliberately not linked from anywhere in the real app's navigation,
      // and compiled out of release builds entirely.
      if (kDebugMode)
        GoRoute(
          path: '/debug/live-session',
          builder: (context, state) => const LiveSessionDebugHarnessScreen(),
        ),
    ],
  );
});
