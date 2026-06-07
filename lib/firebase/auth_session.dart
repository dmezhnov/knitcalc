/// An authenticated Firebase session: the signed-in user's identity plus the
/// tokens needed to call Firestore on their behalf.
///
/// The [idToken] is short-lived (~1h) and is refreshed with the long-lived
/// [refreshToken] via [FirebaseAuthClient.refresh]. The whole session is
/// persisted locally so a sign-in survives app restarts.
library;

class AuthSession {
  const AuthSession({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    this.emailVerified = false,
    this.photoUrl,
  });

  /// Builds a session from an Identity Toolkit `signUp`/`signInWithPassword`
  /// response (camelCase fields, `expiresIn` in seconds as a string). The
  /// response does not carry verification state; it is filled in via a separate
  /// lookup, so it defaults to `false` here.
  factory AuthSession.fromSignInResponse(Map<String, dynamic> json) {
    return AuthSession(
      uid: json['localId'] as String,
      email: json['email'] as String? ?? '',
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: _expiry(json['expiresIn']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  /// Builds a session from a Secure Token `token` (refresh) response, whose
  /// fields are snake_case and which omits the email and verification flag (both
  /// carried over from the previous session).
  factory AuthSession.fromRefreshResponse(
    Map<String, dynamic> json, {
    required String email,
    required bool emailVerified,
    String? photoUrl,
  }) {
    return AuthSession(
      uid: json['user_id'] as String,
      email: email,
      idToken: json['id_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: _expiry(json['expires_in']),
      emailVerified: emailVerified,
      photoUrl: photoUrl,
    );
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      uid: json['uid'] as String,
      email: json['email'] as String,
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      emailVerified: json['emailVerified'] as bool? ?? false,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  /// Firebase user id; also the Firestore document path segment for this user.
  final String uid;
  final String email;

  /// Short-lived bearer token for Firestore REST calls.
  final String idToken;

  /// Long-lived token used to mint a fresh [idToken] once it expires.
  final String refreshToken;

  /// Absolute time the [idToken] stops being valid.
  final DateTime expiresAt;

  /// Whether the account's email has been confirmed via the verification link.
  final bool emailVerified;

  /// Profile picture URL, when the identity provider supplies one (Google).
  final String? photoUrl;

  /// Whether the id token is expired or close enough to expiry that it should be
  /// refreshed before the next call.
  bool get needsRefresh =>
      DateTime.now().add(const Duration(minutes: 5)).isAfter(expiresAt);

  AuthSession copyWith({bool? emailVerified}) {
    return AuthSession(
      uid: uid,
      email: email,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      emailVerified: emailVerified ?? this.emailVerified,
      photoUrl: photoUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'emailVerified': emailVerified,
    'photoUrl': photoUrl,
  };

  static DateTime _expiry(Object? expiresIn) {
    final seconds = int.tryParse(expiresIn?.toString() ?? '') ?? 3600;
    return DateTime.now().add(Duration(seconds: seconds));
  }
}
