import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/app_user.dart';

/// The only place `firebase_auth`/`google_sign_in` may be imported from.
/// Everything above this layer talks to [AuthRepository], never to Firebase
/// or Google Sign-In types directly.
abstract class AuthRepository {
  /// Emits the current user (or null) whenever Firebase Auth's sign-in state
  /// changes. This is the single source of truth the router's redirect guard
  /// watches.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Runs the interactive Google sign-in flow and signs the result into
  /// Firebase Auth. Returns null if the user cancelled the picker rather than
  /// throwing — cancellation is a normal outcome, not a failure.
  Future<AppUser?> signInWithGoogle();

  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
      : _firebaseAuth = firebaseAuth ?? fb.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final fb.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize();
    _googleSignInInitialized = true;
  }

  @override
  Stream<AppUser?> authStateChanges() =>
      _firebaseAuth.authStateChanges().map(_mapUser);

  @override
  AppUser? get currentUser => _mapUser(_firebaseAuth.currentUser);

  @override
  Future<AppUser?> signInWithGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
    } catch (_) {
      throw const AppException(
        "Google sign-in isn't available right now. Check your connection and try again.",
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw AppException(
        'Google sign-in failed: ${e.description ?? e.code.toString()}',
      );
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AppException(
        "Google didn't give us what we needed to sign you in. Try again.",
      );
    }

    try {
      final credential = fb.GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = _mapUser(userCredential.user);
      if (user == null) {
        throw const AppException("Sign-in didn't complete. Try again.");
      }
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw AppException(e.message ?? 'Sign-in failed. Try again.');
    }
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best-effort: Firebase sign-out already succeeded, which is what
      // actually gates access to the app.
    }
  }

  AppUser? _mapUser(fb.User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

/// Single source of truth for "who is signed in" — the router's redirect
/// guard watches this, combined with profile existence.
final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});
