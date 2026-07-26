/// A typed failure that can safely cross layer boundaries.
///
/// Repositories in `data/` catch raw platform exceptions (FirebaseException,
/// GoogleSignInException, etc.) and rethrow this instead, so nothing above
/// `data/` ever needs to know about a specific backend's exception types.
class AppException implements Exception {
  const AppException(this.message);

  /// A plain-language message safe to show directly in the UI.
  final String message;

  @override
  String toString() => message;
}
