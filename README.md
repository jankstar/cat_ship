# cat_ship

A App for cats to hunt ships.

## start 

in debug mode <br>
```flutter run```

for direct deployment on ios and mac<br>
```flutter build ios --release && ios-deploy --bundle build/ios/iphoneos/Runner.app```
```flutter build macos --release ```


new packages <br>
```cd ios && pod install && cd ..```
```cd macos && pod install && cd ..```

## generate icons
```flutter pub run flutter_launcher_icons```

## Localization

```flutter gen-l10n```

This project generates localized messages based on arb files found in
the `lib/src/l10n` directory.

To support additional languages, please visit the tutorial on
[Internationalizing Flutter
apps](https://flutter.dev/docs/development/accessibility-and-localization/internationalization)

