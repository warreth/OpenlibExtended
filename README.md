<div align="center">

<img src="assets/icons/appIcon.png" width="150">

# OpenlibExtended
> I made this fork to keep using the app. It’s intended for personal use; I’ll keep it updated, but don’t expect weekly releases.
> 
> See [here](https://github.com/warreth/OpenlibExtended/?tab=readme-ov-file#features-) to view all the features that i've added to the original version.


An Open source app to download and read books from shadow library ([Anna’s Archive](https://annas-archive.org/))

[![made-with-flutter](https://img.shields.io/badge/Made%20with-Flutter-4361ee.svg?style=for-the-badge)](https://flutter.dev/)
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-e63946.svg?style=for-the-badge)](https://opensource.org/licenses/)
[![Latest release](https://img.shields.io/github/release/warreth/OpenlibExtended.svg?style=for-the-badge)](https://github.com/warreth/OpenlibExtended/releases)
[![Downloads](https://img.shields.io/github/downloads/warreth/OpenlibExtended/total.svg?style=for-the-badge)](https://github.com/warreth/OpenlibExtended/releases)

[<img src="github_releases.png"
     alt="Get it on GitHub"
     height="60">](https://github.com/warreth/OpenlibExtended/releases)
</div>

## Note 📝

**WARNING:** This App Is In Beta Stage, So You May Encounter Bugs. If You Do, Open An Issue In Github Repository.

**Publishing OpenlibExtended, Or Any Fork Of It In The Google Play Store Violates Their Terms And Conditions**

## Screenshots 🖼️

[<img src="screenshots/Screenshot_1.png" width=160>](screenshots/Screenshot_1.png)
[<img src="screenshots/Screenshot_2.png" width=160>](screenshots/Screenshot_2.png)
[<img src="screenshots/Screenshot_3.png" width=160>](screenshots/Screenshot_3.png)
[<img src="screenshots/Screenshot_4.png" width=160>](screenshots/Screenshot_4.png)
[<img src="screenshots/Screenshot_5.png" width=160>](screenshots/Screenshot_5.png)
[<img src="screenshots/Screenshot_6.png" width=160>](screenshots/Screenshot_6.png)
[<img src="screenshots/Screenshot_7.png" width=160>](screenshots/Screenshot_7.png)
[<img src="screenshots/Screenshot_8.png" width=160>](screenshots/Screenshot_8.png)

## Description 📖

OpenlibExtended Is An Open Source App To Download And Read Books From Shadow Library ([Anna’s Archive](https://annas-archive.org/)). The App Has Built In Reader to Read Books

As [Anna’s Archive](https://annas-archive.org/) Doesn't Have An API. The App Works By Sending Request To Anna’s Archive And Parses The Response To objects. The App Extracts The Mirrors From Response And Downloads The Book

## Features ✨

- **Multi-Instance Support** - Configure multiple Anna's Archive mirrors with automatic failover
  - 6 pre-configured instances (Anna's Archive .gs, .se, .li, .st, .pm + welib.org)
  - Add custom mirror instances
  - Drag-to-reorder priority
  - Enable/disable instances
  - Automatic retry (2x per instance) with seamless fallback
    
- **Background Downloads** - Download books in the background with progress notifications
  - Queue multiple books for simultaneous download
  - Progress notifications with real-time updates
  - Downloads continue even when app is in background
  - Visual download queue in Home, Search, and My Library pages
    
- **Built-In Reader** - Read books with intuitive navigation
  - Supports Epub And Pdf Formats
  - **Tap navigation: tap left/right sides of screen to navigate pages**
  - Arrow button navigation and swipe gestures also supported
  - Works great on phones and tablets
- Trending Books
- Open Books In Your Favourite Ebook Reader
- Filter Books
- Sort Books

## Roadmap 🎯

- Adding More Book Format supports (cbz,cbr,azw3,etc...)
- Add Booklore support (syncing to and from booklore server)
- Make Linux/Desktop version
- Make web version

## Screen Layout

```
┌─────────────────────────────────────────────┐
│                                             │
│  ◄─────────┐     NO ACTION    ┌─────────►  │
│            │                  │             │
│   PREVIOUS │                  │    NEXT    │
│    PAGE/   │                  │   PAGE/    │
│  CHAPTER   │                  │  CHAPTER   │
│            │                  │             │
│            │                  │             │
│   [30%]    │      [40%]       │   [30%]    │
│            │                  │             │
│  Tap here  │   Text selection │  Tap here  │
│  to go     │   and scrolling  │  to go     │
│  backward  │   work here      │  forward   │
│            │                  │             │
└─────────────────────────────────────────────┘
```

### Why This Layout?

1. **Natural Reading Flow**: Matches left-to-right reading pattern
2. **Easy Thumb Access**: Comfortable for one-handed use
3. **Accident Prevention**: Center zone prevents accidental page changes
4. **Text Selection**: Center zone allows selecting and copying text
5. **Tablet Friendly**: Larger zones on bigger screens are easier to hit

## Building from Source

- If you don't have Flutter SDK installed, please visit official [Flutter](https://flutter.dev) site.

- Git Clone The Repo

     ```sh
     git clone https://github.com/warreth/OpenlibExtended.git
     ```

- Run the app with Android Studio or VS Code. Or the command line:

     ```sh
     flutter pub get
     flutter run
     ```

- To Build App Run:

     ```sh
     flutter build
     ```

- The Build Will Be In './build/app/outputs/flutter-apk/app-release.apk'

### Retrying CI/CD Builds

To manually retry a failed build in GitHub Actions:

1. Go to the [Actions tab](https://github.com/warreth/OpenlibExtended/actions) in the repository
2. Click on the failed workflow run
3. Click the "Re-run jobs" button in the top right corner
4. Select "Re-run failed jobs" or "Re-run all jobs"

Alternatively, you can trigger a new release build by creating a new release tag.

### Manual Build (Without Release)

You can manually trigger a build without creating a release to test your changes:

1. Go to the [Actions tab](https://github.com/warreth/OpenlibExtended/actions) in the repository
2. Click on "Build and Release APKs" workflow on the left sidebar
3. Click "Run workflow" button (top right)
4. Optionally:
   - Enter a version number (e.g., 1.0.12) or leave empty to use current version from pubspec.yaml
   - Check "Skip running tests" if you want to skip tests
5. Click the green "Run workflow" button
6. Wait for the build to complete
7. Download the APK artifacts from the workflow run page

### Android

Make sure that `android/local.properties` has `flutter.minSdkVersion=21` or above
For setup guide see [SETUP.md](./SETUP.md)

## Contributor required 🚧

We are actively seeking contributors. Whether you're a seasoned developer or just starting out, we welcome your contributions to help make this project even better!

## Contribution 💝

Whether you have ideas, design changes or even major code changes, help is always welcome. The app gets better and better with each contribution, no matter how big or small!

If you'd like to get involved See [CONTRIBUTING.md](./CONTRIBUTING.md) for the guidelines.

## Issues 🚩

Please report bugs via the [issue tracker](https://github.com/warreth/OpenlibExtended/issues).

## Donate 🎁

If you like OpenlibExtended, you're welcome to send a donation.

[Donate To Anna’s Archive.](https://annas-archive.org/donate?tier=1)

## License 📜

[![GNU GPLv3 Image](https://www.gnu.org/graphics/gplv3-127x51.png)](https://www.gnu.org/licenses/gpl-3.0.en.html)  

OpenlibExtended is a free software licensed under GPL v3.0 It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY. [GNU General Public License](https://www.gnu.org/licenses/gpl.html) as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

## Disclaimer ⚠️

OpenlibExtended does not own or have any affiliation with the books available through the app. All books are the property of their respective owners and are protected by copyright law. OpenlibExtended is not responsible for any infringement of copyright or other intellectual property rights that may result from the use of the books available through the app. By using the app, you agree to use the books only for personal, non-commercial purposes and in compliance with all applicable laws and regulations.
