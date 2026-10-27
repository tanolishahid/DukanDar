# DukanDar

Inventory, sales, credit (udhaar) and dashboard for a laptop and accessories shop.
Works offline on Android and Windows, syncs to the cloud (Supabase) when internet is available.

## One-time setup on your computer

You need: Flutter (stable), Android Studio (for the Android build), and on Windows
"Visual Studio 2022 with Desktop development with C++" (for the Windows build).
Turn on Windows **Developer Mode** (Settings > For developers), Flutter needs it.

```
cd dukandar
flutter create --platforms=android,windows --project-name dukandar --org com.dukandar .
dart run tool/setup_project.dart
flutter pub get
flutter run -d windows        # or: flutter run   (with an Android phone plugged in)
```

`flutter create .` keeps the files already in `lib/` and `pubspec.yaml`.
If it replaces `pubspec.yaml`, copy the `dependencies:` list from this project's version back in.

## Try it without the cloud

Leave `lib/config.dart` as it is. The app then runs in **local-only mode**: no login, no sync,
everything stored on the device. Good for testing the four tabs.

## Turn on the cloud (Supabase)

1. supabase.com -> New project.
2. SQL Editor -> New query -> paste all of `supabase/schema.sql` -> Run.
3. Authentication -> Providers -> Email -> turn **Confirm email OFF**.
4. Project Settings -> API: copy the **Project URL** and the **anon public key** into `lib/config.dart`.
5. Run the app. Choose **New shop** to create your shop and owner account.
6. Menu -> **Staff** to add staff. They sign in with the shop code, username and password.

## Switching a shop on or off (your payment collection)

Supabase -> Table Editor -> `shops` -> change `active_until`. After that date the shop is
blocked in the app and on the server. New shops start with a 30-day trial.

## Build installable files

```
flutter build apk --release        # Android: build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release    # Windows: build/windows/x64/runner/Release/
```
