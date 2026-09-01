// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'Home';

  @override
  String get navSearch => 'Search';

  @override
  String get navMyLibrary => 'My Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get advancedSearch => 'Advanced Search';

  @override
  String get author => 'Author';

  @override
  String get publisher => 'Publisher';

  @override
  String get searchLibraryHint =>
      'Search library (title, author, publisher, year)';

  @override
  String get newCollection => 'New collection';

  @override
  String get noResultsFound => 'No results found';

  @override
  String resultsFor(String query) {
    return 'Results for \'$query\'';
  }

  @override
  String get followSystem => 'Follow the System';

  @override
  String get lightTheme => 'Light theme';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get languageSetting => 'Language';

  @override
  String get systemLanguage => 'System default';

  @override
  String get enableNotifications => 'Enable Notifications';

  @override
  String get notificationsExplanation =>
      'OpenlibExtended needs notification permission to show download progress in the background. This helps you track your book downloads even when the app is minimized.';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get enable => 'Enable';

  @override
  String get statusUnread => 'Unread';

  @override
  String get statusInProgress => 'In Progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get collectionNameHint => 'e.g. Favorites, Sci-Fi';

  @override
  String get manageCollectionsHint =>
      'Long-press any book to manage its collections';

  @override
  String get results => 'Results';

  @override
  String get loading => 'Loading...';

  @override
  String get unknown => 'Unknown';

  @override
  String get about => 'About';

  @override
  String get aboutDescription =>
      'An Open source app to download and read books from shadow library (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'This is a forked version maintained by warreth for personal use and community updates.';

  @override
  String get aboutOriginalNote =>
      'Original app by dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Version';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'This Fork (by warreth)';

  @override
  String get reportAnIssue => 'Report An Issue';

  @override
  String get originalProject => 'Original Project (by dstark5)';

  @override
  String get licence => 'Licence';

  @override
  String get gplLicense => 'GPL v3.0 license';

  @override
  String couldNotLaunch(String url) {
    return 'Could not launch $url';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get searchProvidersSection => 'Search Providers';

  @override
  String get libraryInstancesSection => 'Library & Instances';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get generalSection => 'General';

  @override
  String get readerSection => 'Reader';

  @override
  String get advancedSection => 'Advanced';

  @override
  String get backupSection => 'Backup';

  @override
  String get updatesSection => 'Updates';

  @override
  String get aboutSection => 'About';

  @override
  String get archiveInstance => 'Archive Instance';

  @override
  String get mirrorsAndProviders => 'Mirrors & Providers';

  @override
  String get fontSizeTitle => 'Font Size';

  @override
  String scaleValue(String value) {
    return 'Scale: ${value}x';
  }

  @override
  String get preview => 'Preview';

  @override
  String get storageLocation => 'Storage Location';

  @override
  String get openPdfExternally => 'Open PDF externally';

  @override
  String get useDefaultPdfViewer => 'Use your default PDF viewer';

  @override
  String get openEpubExternally => 'Open EPUB externally';

  @override
  String get useDefaultEpubReader => 'Use your default EPUB reader';

  @override
  String get manualDownloadButton => 'Manual Download Button';

  @override
  String get showManualDownloadHint =>
      'Show button to manually trigger downloads';

  @override
  String get donationKeyTitle => 'Anna\'s Archive Donation Key';

  @override
  String get enterKeyForFasterDownloads => 'Enter key for faster downloads';

  @override
  String get aboutOpenlib => 'About OpenlibExtended';

  @override
  String get redoOnboarding => 'Redo Onboarding';

  @override
  String get resetAppSetup => 'Reset app setup and start over';

  @override
  String get exportLogs => 'Export Logs';

  @override
  String get shareDiagnosticLogs => 'Share diagnostic logs (last 5 min)';

  @override
  String failedExportLogs(String error) {
    return 'Failed to export logs: $error';
  }

  @override
  String get donationKeyDialog => 'Donation Key';

  @override
  String get enterYourKey => 'Enter your key';

  @override
  String get instanceChanged => 'Instance changed successfully';

  @override
  String rankingFailed(String error) {
    return 'Ranking failed: $error';
  }

  @override
  String get autoRankInstances => 'Auto-Rank Instances';

  @override
  String get sortBySpeedOnStartup => 'Automatically sort by speed on startup';

  @override
  String get rankInstancesNow => 'Rank Instances Now';

  @override
  String onLatestVersion(String version) {
    return 'You\'re on the latest version ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Failed to check for updates: $error';
  }

  @override
  String get includeBetaUpdates => 'Include Beta Updates';

  @override
  String get getPreReleaseVersions => 'Get pre-release versions';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get backupSaved => 'Backup saved';

  @override
  String failedExportBackup(String error) {
    return 'Failed to export backup: $error';
  }

  @override
  String get backupRestored => 'Backup restored';

  @override
  String failedImportBackup(String error) {
    return 'Failed to import backup: $error';
  }

  @override
  String get atLeastOneSource => 'At least one search source is needed';

  @override
  String rankedFastest(String name, String time) {
    return 'Ranked! Fastest: $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Ranking complete';

  @override
  String get providerSourceOriginal => 'The app\'s original source';

  @override
  String get providerLibgenCatalog => 'libgen.is public catalog';

  @override
  String get providerZlibMirrors => 'Mirrors rotate; may need a login';

  @override
  String get themeTitle => 'Theme';

  @override
  String get saveBackupTitle => 'Save Backup';

  @override
  String get pickBackupFile => 'Pick a backup file';

  @override
  String get notABackup => 'That file is not an OpenlibExtended backup';

  @override
  String get donationKeyHelper =>
      'Used for faster downloads on Anna\'s Archive';

  @override
  String get mirrorsTestedRanked => 'Mirrors tested and ranked by speed';

  @override
  String testingFailed(String error) {
    return 'Testing failed: $error';
  }

  @override
  String get addCustomMirror => 'Add Custom Mirror';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameHint => 'e.g., My LibGen mirror';

  @override
  String get serviceLabel => 'Service';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Please fill all fields';

  @override
  String get enterValidUrl =>
      'Please enter a valid URL with http:// or https://';

  @override
  String get mirrorAdded => 'Mirror added successfully';

  @override
  String get deleteMirror => 'Delete Mirror';

  @override
  String deleteMirrorConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get mirrorDeleted => 'Mirror deleted';

  @override
  String get cannotDeleteDefaultMirrors => 'Cannot delete default mirrors';

  @override
  String get manageMirrors => 'Manage Mirrors';

  @override
  String get noMirrorsAvailable => 'No mirrors available';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get addMirror => 'Add mirror';

  @override
  String get testRankMirrors => 'Test & rank mirrors by speed';

  @override
  String get unreachable => 'unreachable';

  @override
  String get open => 'Open';

  @override
  String get unableToOpenFile => 'Unable to open file!';

  @override
  String get openInSite => 'Open in site';

  @override
  String get bookDeleted => 'Book has been Deleted!';

  @override
  String get deleteBook => 'Delete Book';

  @override
  String get deletePermanentWarning => 'This is permanent and cannot be undone';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get showBlockedContent => 'Show blocked page content';

  @override
  String get verifyInBrowser => 'Verify in Browser';

  @override
  String get manualVerificationRequired => 'Manual Verification Required';

  @override
  String get systemBrowser => 'System Browser';

  @override
  String get embeddedBrowser => 'Embedded Browser';

  @override
  String get unableToOpenVerification =>
      'Unable to open verification page - no URL available';

  @override
  String get blockedPageContent => 'Blocked Page Content';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get gotIt => 'Got it!';

  @override
  String get copy => 'Copy';

  @override
  String get tryUsingVpn => 'Try using a VPN';

  @override
  String get trending => 'Trending';

  @override
  String get genres => 'Genres';

  @override
  String get copiedBookPath => 'Copied the book path to your clipboard';

  @override
  String get pauseDownload => 'Pause download';

  @override
  String get resumeDownload => 'Resume download';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get copiedBookLink => 'Copied the book link to your clipboard';

  @override
  String get noMirrors => 'No mirrors available!';

  @override
  String get addToMyLibrary => 'Add To My Library';

  @override
  String get downloadStartedBackground => 'Download started in background';

  @override
  String get bookDownloaded => 'Book has been downloaded!';

  @override
  String get selectStorageToContinue =>
      'Please select a storage folder to continue';

  @override
  String get getStarted => 'Get Started';

  @override
  String get next => 'Next';

  @override
  String get welcomeTitle => 'Welcome to OpenlibExtended';

  @override
  String get welcomeSubtitle =>
      'Your personal gateway to a world of knowledge. Let\'s get you set up.';

  @override
  String get whereToStoreBooks => 'Where should we store your books?';

  @override
  String get noPathSelected => 'No path selected';

  @override
  String get selectFolder => 'Select Folder';

  @override
  String get storageScanNote =>
      'We\'ll only look for PDF/EPUB files in this folder. No recursive scanning of subfolders.';

  @override
  String get automaticUpdates => 'Automatic Updates';

  @override
  String get enableAutoUpdates => 'Enable Auto-Updates';

  @override
  String get autoUpdatesFdroidNote =>
      'Not recommended if you installed via F-Droid (F-Droid handles updates).';

  @override
  String get enableBetaUpdatesOnboarding => 'Enable Beta Updates';

  @override
  String get betaUpdatesNote =>
      'Get pre-release versions (beta updates) when available.';

  @override
  String get supportAnnasArchive => 'Support Anna\'s Archive';

  @override
  String get donationPitch =>
      'Donating to Anna\'s Archive provides faster downloads and helps them keep the service running for everyone. You can enter your secret key below.';

  @override
  String get annasSecretKey => 'Anna\'s Archive Secret Key';

  @override
  String get supportThisApp => 'Support This App';

  @override
  String get sponsorPitch =>
      'If you enjoy this app, consider supporting its development. It helps me dedicate more time to making it better!';

  @override
  String get sponsorOnGithub => 'Sponsor on GitHub';

  @override
  String get stayUpdated => 'Stay Updated';

  @override
  String get notifyOnComplete => 'Get notified when downloads complete.';

  @override
  String get chooseTheme => 'Choose a Theme';

  @override
  String get lightThemeShort => 'Light';

  @override
  String get darkThemeShort => 'Dark';

  @override
  String get verifyingAccess => 'Verifying Access';

  @override
  String get done => 'Done';

  @override
  String get nothingToRead => 'Nothing to read on this page';

  @override
  String get noVoiceAvailable => 'No voice available for reading aloud';

  @override
  String get pauseReadingAloud => 'Pause reading aloud';

  @override
  String get resumeReadingAloud => 'Read aloud';

  @override
  String get stopReadingAloud => 'Stop reading aloud';

  @override
  String get speechSpeed => 'Speech speed';

  @override
  String get decreaseFontSize => 'Decrease font size';

  @override
  String get increaseFontSize => 'Increase font size';

  @override
  String get close => 'Close';

  @override
  String get sortLibrary => 'Sort library';

  @override
  String get reloadHealthData => 'Reload health data';

  @override
  String addServiceMirror(String title) {
    return 'Add a $title mirror';
  }

  @override
  String get deleteMirrorTooltip => 'Delete mirror';
}
