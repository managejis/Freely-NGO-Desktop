# Freely NGO for Windows (Flutter desktop)

The desktop edition of Freely NGO. It uses **the same Google Sheet as the mobile app**: the same Apps Script web app, the same NGO code,
the same invite / admin-key login, the same roles and branch rules, the same record formats. Records entered on a phone appear here after
a sync and the other way round.

## First start
* **A new PC is a new device.** Choose **I am a user**, enter your mobile number, name and the NGO's **invite code** (Users screen of the
  mobile app > Invite code) and the admin approves this PC once, exactly like a phone. Afterwards the app opens straight in.
* **The admin on a new PC:** choose **I am the admin**, then **New phone? Enter admin key** (the admin key is in Settings on the phone).
* The script is the same one: `assets/freely_ngo_apps_script.txt` (identical to the mobile app). If you update the script, update it in
  both apps. This desktop edition needs the script version **with leave management** (Leave tab).

## What is different from the phone
| Phone | Windows |
|---|---|
| Bottom bar and floating + button | Sidebar (labels, icon rail or drawer by window width) and a "Quick add" button |
| Share sheet | "Save as" dialog for backups and Excel / PDF reports; receipts, notices and invite messages are **copied to the clipboard** |
| Gallery picker for the logo | File picker (the picture is shrunk to 160 px) |
| SQLite through the phone plugin | SQLite through FFI, stored in `%APPDATA%\ManageJi\Freely NGO` |

## Responsive layout
* 1100 px and wider: full sidebar with labels, content centred (max 1100 px, forms 760 px).
* 720 - 1100 px: narrow icon rail (tooltips), "More" menu for the account pages.
* below 720 px (down to 420 px): top bar + drawer; every grid reflows to fewer columns.

The window can be resized freely (minimum 420 x 560). `test/shell_test.dart` renders the real app against a real SQLite file at six
window sizes (1920, 1366, 1100, 820, 600 and 420 px wide) and fails on any layout overflow.

## Build
```
# Visual Studio 2022 with "Desktop development with C++" and Windows Developer Mode are required
powershell -ExecutionPolicy Bypass -File build_windows.ps1
```
Result: `build\windows\x64\runner\Release\FreelyNGO.exe` (keep the whole Release folder together) and `build\Freely-NGO-Windows.zip`.

## Develop
```
flutter pub get
flutter test        # logic tests + real widget tests at several window sizes (no Visual Studio needed)
flutter run -d windows
```

## Not in this release
Same list as the mobile app (photos / attachments, push notifications, scheduled backups, other languages), plus an installer
(MSIX / Inno Setup): the build is a zip of the Release folder.
