# Public Firebase build configuration

These JSON files contain Firebase's public client configuration for the selected
Recall project, `recall-f1d1e`. They contain no Firebase administrative keys or AI
provider secrets. Use the file matching the Flutter build target:

```sh
flutter build web --release --dart-define-from-file=config/firebase/web.json
flutter build apk --debug --dart-define-from-file=config/firebase/android.json
flutter build ios --simulator --debug --dart-define-from-file=config/firebase/ios.json
```

The Android app is registered as `com.recharge.recall_next`; the iOS app is
registered as `com.recharge.recallNext`. These remain separate from the original
Android app. Provider and administrative secrets belong only in server secret
configuration. An API URL in a build does not prove that the server has been
deployed; see [deployment status](../../docs/FIREBASE_DEPLOYMENT.md).

[Firebase's explanation of public configuration](https://firebase.google.com/docs/projects/learn-more#config-files-objects).
