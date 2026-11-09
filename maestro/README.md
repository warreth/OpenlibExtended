# Maestro end-to-end flows

These flows drive the real Android app through the paths a user takes:
onboarding, a live search, a real book download and the mirror list.
They hit the real providers (open-slum.org, libgen, Anna's Archive,
Z-Library, WeLib), so they need network access and a few minutes.

## Prerequisites

- [Maestro](https://maestro.mobile.dev/) on the host (`maestro --version`).
- An Android emulator or device (`adb devices` shows it).
- The **debug** APK installed. The startup update dialog is part of the
  flows; the debug build's version is below the latest release, so the
  dialog reliably appears and `dismiss_dialogs.yaml` can close it.

```bash
flutter build apk --debug --target-platform android-x64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Run

```bash
./maestro/run.sh
```

The flows share state and must run in order:

| Flow | What it proves |
| --- | --- |
| `01_onboarding.yaml` | First run reaches the main screen. |
| `02_search.yaml` | A live search returns results and a book page opens. |
| `03_download_and_read.yaml` | The book downloads, lands in My Library and opens in the reader. |
| `04_mirrors.yaml` | Every service and its live mirror rows load from open-slum.org. |

`dismiss_dialogs.yaml` is a shared subflow that closes the startup update
dialog and the notification prompt.

## Notes

- `02_search.yaml` taps the first result card rather than a fixed title,
  so it keeps working as editions and rankings change.
- `03_download_and_read.yaml` accepts a book that is already in the
  library (it shows Open instead of Add To My Library).
- A run against a release build with no newer version will fail in
  `dismiss_dialogs.yaml`, which waits for the update dialog on purpose.
