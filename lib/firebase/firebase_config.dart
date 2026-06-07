/// Public client configuration for the KnitCalc Firebase project.
///
/// The API key is a browser/client key that is meant to ship inside the app —
/// access to data is gated by Firestore security rules tied to the signed-in
/// user, not by keeping this key secret. Sync talks to Firebase entirely over
/// REST (no native FlutterFire SDK), so this is all the configuration needed on
/// every platform, including Linux/Windows desktop where the SDK has no support.
library;

class FirebaseConfig {
  const FirebaseConfig({required this.projectId, required this.apiKey});

  final String projectId;
  final String apiKey;
}

const FirebaseConfig firebaseConfig = FirebaseConfig(
  projectId: 'knitcalc-sync',
  apiKey: 'AIzaSyC-MwXUb_ln2rr_1wRXSowLRIHze6i_o-U',
);
