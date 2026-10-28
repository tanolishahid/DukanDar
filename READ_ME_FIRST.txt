Extract this zip INTO your dukandar project folder and choose "Replace files" when asked.
(The folder that contains pubspec.yaml, lib, web and supabase.)

Then:
1. Supabase > SQL Editor > New query > paste supabase/migration_002_bills.sql > Run   (do this FIRST)
2. In the project folder run:
     git add -A
     git commit -m "Multi-item bills, repair lines, discount, slip printing, past sales import"
     git push
3. Wait for the Android and web builds in the Actions tab. Install the new APK on phones.
