# YoVoice profile recovery fix

This package is cumulative and contains the complete `lib` folder from Stage 5.2 plus the corrected Stage 5.3 profile files.

1. Back up your current `lib` folder.
2. Replace the entire project `lib` folder with the `lib` folder from this package.
3. Replace `firebase.json` and `storage.rules` in the project root.
4. In Firebase Console, open Storage and click **Get started** to create the bucket.
5. Run:

```bash
firebase deploy --only storage
flutter pub get
flutter analyze
```
