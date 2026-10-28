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

## Run it in a browser (web app, for laptops)

The same app also runs in Chrome / Edge. Data is saved inside the browser
(works offline after the first visit) and syncs to Supabase like the phone app.

```
flutter create --platforms=web .          # only if the web/ folder is missing
dart run sqflite_common_ffi_web:setup     # adds sqlite3.wasm and sqflite_sw.js to web/
flutter run -d chrome
flutter build web --release --no-web-resources-cdn
```

**Hosting (free, automatic):** push to `main`. The workflow `.github/workflows/deploy-web.yml` (move `deploy-web.yml` from the project root into that folder first)
builds the site and publishes it to GitHub Pages. One-time: repo **Settings -> Pages ->
Source = GitHub Actions**. The address will be `https://<your-username>.github.io/<repo-name>/`.

**Install like a program:** open the address in Chrome or Edge, then use the
"Install" icon in the address bar. It gets its own window and desktop icon.

Note: browser data belongs to one browser on one computer. Turn on the cloud (Supabase)
so shop data is also safe online and shared with phones.

## Bills, repairs, discounts and printing

Sales are now **bills**: one bill can hold many items (laptop, mouse, USB...), repair / service
lines, a discount for the whole bill, and a part payment (the rest goes to the Credit tab).
A customer who only comes for a repair gets a repair-only bill.

After saving, **Print slip** (58 mm roll, 80 mm roll or A4) or **Share as PDF**. The slip shows the
shop name, address and phone, never your purchase price or profit. Everything works offline.

**Shop name, phone and address** are asked when the owner creates the shop. The owner can change
them later in the menu: *Shop name, phone, address*.

**Past sales:** Sales > *Import past sales* brings in years of history from Excel (see
`DukanDar_past_sales_import_template.xlsx`). Old sales do not change current stock.

### Upgrading an existing Supabase project (do this BEFORE installing the new app)

Supabase > SQL Editor > New query > paste `supabase/migration_002_bills.sql` > Run.
Then update every phone / computer to the new version. New projects run `schema.sql` first and
the migration after it.

## Categories

Inventory has three sections: **Laptop**, **Computer** (Desktop PC, Gaming PC, All-in-One,
Mini PC, Workstation, Server) and **Accessory** (keyboard, mouse, LCD, LED, graphic card,
processor, motherboard, power supply, casing, cooler, HDD, printer, UPS, router and more;
"Other" lets you type any new type). Excel/CSV import detects these automatically.

## Build installable files

```
flutter build apk --release        # Android: build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release    # Windows: build/windows/x64/runner/Release/
```
