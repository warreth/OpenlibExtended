// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'Accueil';

  @override
  String get navSearch => 'Rechercher';

  @override
  String get navMyLibrary => 'Ma bibliothèque';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get add => 'Ajouter';

  @override
  String get delete => 'Supprimer';

  @override
  String get retry => 'Réessayer';

  @override
  String get advancedSearch => 'Recherche avancée';

  @override
  String get author => 'Auteur';

  @override
  String get publisher => 'Éditeur';

  @override
  String get searchLibraryHint =>
      'Rechercher dans la bibliothèque (titre, auteur, éditeur, année)';

  @override
  String get newCollection => 'Nouvelle collection';

  @override
  String get noResultsFound => 'Aucun résultat trouvé';

  @override
  String resultsFor(String query) {
    return 'Résultats pour « $query »';
  }

  @override
  String get followSystem => 'Suivre le système';

  @override
  String get lightTheme => 'Thème clair';

  @override
  String get darkTheme => 'Thème sombre';

  @override
  String get languageSetting => 'Langue';

  @override
  String get systemLanguage => 'Langue du système';

  @override
  String get enableNotifications => 'Activer les notifications';

  @override
  String get notificationsExplanation =>
      'OpenlibExtended a besoin de l\'autorisation de notification pour afficher la progression des téléchargements en arrière-plan. Vous pouvez ainsi suivre vos téléchargements de livres même lorsque l\'application est réduite.';

  @override
  String get maybeLater => 'Peut-être plus tard';

  @override
  String get enable => 'Activer';

  @override
  String get statusUnread => 'Non lu';

  @override
  String get statusInProgress => 'En cours';

  @override
  String get statusCompleted => 'Terminé';

  @override
  String get collectionNameHint => 'ex. Favoris, Science-fiction';

  @override
  String get manageCollectionsHint =>
      'Appuyez longuement sur un livre pour gérer ses collections';

  @override
  String get results => 'Résultats';

  @override
  String get loading => 'Chargement...';

  @override
  String get unknown => 'Inconnu';

  @override
  String get about => 'À propos';

  @override
  String get aboutDescription =>
      'Une application open source pour télécharger et lire des livres de bibliothèques parallèles (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'Version forkée maintenue par warreth pour un usage personnel et des mises à jour communautaires.';

  @override
  String get aboutOriginalNote =>
      'Application originale de dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Version';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'Ce fork (par warreth)';

  @override
  String get reportAnIssue => 'Signaler un problème';

  @override
  String get originalProject => 'Projet original (par dstark5)';

  @override
  String get licence => 'Licence';

  @override
  String get gplLicense => 'Licence GPL v3.0';

  @override
  String couldNotLaunch(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get searchProvidersSection => 'Sources de recherche';

  @override
  String get libraryInstancesSection => 'Bibliothèque et instances';

  @override
  String get appearanceSection => 'Apparence';

  @override
  String get generalSection => 'Général';

  @override
  String get readerSection => 'Lecteur';

  @override
  String get advancedSection => 'Avancé';

  @override
  String get backupSection => 'Sauvegarde';

  @override
  String get updatesSection => 'Mises à jour';

  @override
  String get aboutSection => 'À propos';

  @override
  String get archiveInstance => 'Instance d\'archive';

  @override
  String get mirrorsAndProviders => 'Miroirs et sources';

  @override
  String get fontSizeTitle => 'Taille de police';

  @override
  String scaleValue(String value) {
    return 'Échelle : ${value}x';
  }

  @override
  String get preview => 'Aperçu';

  @override
  String get storageLocation => 'Emplacement de stockage';

  @override
  String get openPdfExternally => 'Ouvrir les PDF à l\'extérieur';

  @override
  String get useDefaultPdfViewer => 'Utiliser votre lecteur PDF par défaut';

  @override
  String get openEpubExternally => 'Ouvrir les EPUB à l\'extérieur';

  @override
  String get useDefaultEpubReader => 'Utiliser votre lecteur EPUB par défaut';

  @override
  String get manualDownloadButton => 'Bouton de téléchargement manuel';

  @override
  String get showManualDownloadHint =>
      'Afficher le bouton pour lancer les téléchargements manuellement';

  @override
  String get donationKeyTitle => 'Clé de don Anna\'s Archive';

  @override
  String get enterKeyForFasterDownloads =>
      'Saisissez la clé pour des téléchargements plus rapides';

  @override
  String get aboutOpenlib => 'À propos d\'OpenlibExtended';

  @override
  String get redoOnboarding => 'Refaire l\'introduction';

  @override
  String get resetAppSetup => 'Réinitialiser la configuration et recommencer';

  @override
  String get exportLogs => 'Exporter les journaux';

  @override
  String get shareDiagnosticLogs =>
      'Partager les journaux de diagnostic (5 dernières min.)';

  @override
  String failedExportLogs(String error) {
    return 'Échec de l\'export des journaux : $error';
  }

  @override
  String get donationKeyDialog => 'Clé de don';

  @override
  String get enterYourKey => 'Saisissez votre clé';

  @override
  String get instanceChanged => 'Instance modifiée avec succès';

  @override
  String rankingFailed(String error) {
    return 'Échec du classement : $error';
  }

  @override
  String get autoRankInstances => 'Classement automatique des instances';

  @override
  String get sortBySpeedOnStartup =>
      'Trier automatiquement par vitesse au démarrage';

  @override
  String get rankInstancesNow => 'Classer les instances maintenant';

  @override
  String onLatestVersion(String version) {
    return 'Vous utilisez la dernière version ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Échec de la vérification des mises à jour : $error';
  }

  @override
  String get includeBetaUpdates => 'Inclure les versions bêta';

  @override
  String get getPreReleaseVersions => 'Recevoir les préversions';

  @override
  String get checkForUpdates => 'Vérifier les mises à jour';

  @override
  String get backupSaved => 'Sauvegarde enregistrée';

  @override
  String failedExportBackup(String error) {
    return 'Échec de l\'export de la sauvegarde : $error';
  }

  @override
  String get backupRestored => 'Sauvegarde restaurée';

  @override
  String failedImportBackup(String error) {
    return 'Échec de l\'import de la sauvegarde : $error';
  }

  @override
  String get atLeastOneSource =>
      'Au moins une source de recherche est nécessaire';

  @override
  String rankedFastest(String name, String time) {
    return 'Classé ! Plus rapide : $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Classement terminé';

  @override
  String get providerSourceOriginal => 'La source d\'origine de l\'application';

  @override
  String get providerLibgenCatalog => 'Catalogue public de libgen.is';

  @override
  String get providerZlibMirrors =>
      'Les miroirs tournent ; connexion parfois requise';

  @override
  String get themeTitle => 'Thème';

  @override
  String get saveBackupTitle => 'Enregistrer la sauvegarde';

  @override
  String get pickBackupFile => 'Choisir un fichier de sauvegarde';

  @override
  String get notABackup =>
      'Ce fichier n\'est pas une sauvegarde OpenlibExtended';

  @override
  String get donationKeyHelper =>
      'Utilisée pour des téléchargements plus rapides sur Anna\'s Archive';

  @override
  String get mirrorsTestedRanked => 'Miroirs testés et classés par vitesse';

  @override
  String testingFailed(String error) {
    return 'Échec du test : $error';
  }

  @override
  String get addCustomMirror => 'Ajouter un miroir personnalisé';

  @override
  String get nameLabel => 'Nom';

  @override
  String get nameHint => 'ex. Mon miroir LibGen';

  @override
  String get serviceLabel => 'Service';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Veuillez remplir tous les champs';

  @override
  String get enterValidUrl =>
      'Veuillez saisir une URL valide avec http:// ou https://';

  @override
  String get mirrorAdded => 'Miroir ajouté avec succès';

  @override
  String get deleteMirror => 'Supprimer le miroir';

  @override
  String deleteMirrorConfirm(String name) {
    return 'Voulez-vous vraiment supprimer « $name » ?';
  }

  @override
  String get mirrorDeleted => 'Miroir supprimé';

  @override
  String get cannotDeleteDefaultMirrors =>
      'Impossible de supprimer les miroirs par défaut';

  @override
  String get manageMirrors => 'Gérer les miroirs';

  @override
  String get noMirrorsAvailable => 'Aucun miroir disponible';

  @override
  String errorLabel(String error) {
    return 'Erreur : $error';
  }

  @override
  String get addMirror => 'Ajouter un miroir';

  @override
  String get testRankMirrors => 'Tester et classer les miroirs par vitesse';

  @override
  String get unreachable => 'inaccessible';

  @override
  String get open => 'Ouvrir';

  @override
  String get unableToOpenFile => 'Impossible d\'ouvrir le fichier !';

  @override
  String get openInSite => 'Ouvrir sur le site';

  @override
  String get bookDeleted => 'Livre supprimé !';

  @override
  String get deleteBook => 'Supprimer le livre';

  @override
  String get deletePermanentWarning =>
      'Cette action est définitive et ne peut pas être annulée';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get showBlockedContent => 'Afficher le contenu de la page bloquée';

  @override
  String get verifyInBrowser => 'Vérifier dans le navigateur';

  @override
  String get manualVerificationRequired => 'Vérification manuelle requise';

  @override
  String get systemBrowser => 'Navigateur système';

  @override
  String get embeddedBrowser => 'Navigateur intégré';

  @override
  String get unableToOpenVerification =>
      'Impossible d\'ouvrir la page de vérification - aucune URL disponible';

  @override
  String get blockedPageContent => 'Contenu de la page bloquée';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get gotIt => 'Compris !';

  @override
  String get copy => 'Copier';

  @override
  String get tryUsingVpn => 'Essayez d\'utiliser un VPN';

  @override
  String get trending => 'Tendances';

  @override
  String get genres => 'Genres';

  @override
  String get copiedBookPath => 'Chemin du livre copié dans le presse-papiers';

  @override
  String get pauseDownload => 'Mettre le téléchargement en pause';

  @override
  String get resumeDownload => 'Reprendre le téléchargement';

  @override
  String get cancelDownload => 'Annuler le téléchargement';

  @override
  String get copiedBookLink => 'Lien du livre copié dans le presse-papiers';

  @override
  String get noMirrors => 'Aucun miroir disponible !';

  @override
  String get addToMyLibrary => 'Ajouter à ma bibliothèque';

  @override
  String get downloadStartedBackground =>
      'Téléchargement lancé en arrière-plan';

  @override
  String get bookDownloaded => 'Livre téléchargé !';

  @override
  String get selectStorageToContinue =>
      'Veuillez sélectionner un dossier de stockage pour continuer';

  @override
  String get getStarted => 'Commencer';

  @override
  String get next => 'Suivant';

  @override
  String get welcomeTitle => 'Bienvenue sur OpenlibExtended';

  @override
  String get welcomeSubtitle =>
      'Votre porte d\'entrée personnelle vers un monde de connaissances. Préparons tout.';

  @override
  String get whereToStoreBooks => 'Où devons-nous stocker vos livres ?';

  @override
  String get noPathSelected => 'Aucun chemin sélectionné';

  @override
  String get selectFolder => 'Choisir un dossier';

  @override
  String get storageScanNote =>
      'Nous ne chercherons que des fichiers PDF/EPUB dans ce dossier. Aucun scan récursif des sous-dossiers.';

  @override
  String get automaticUpdates => 'Mises à jour automatiques';

  @override
  String get enableAutoUpdates => 'Activer les mises à jour automatiques';

  @override
  String get autoUpdatesFdroidNote =>
      'Déconseillé si vous avez installé via F-Droid (F-Droid gère les mises à jour).';

  @override
  String get enableBetaUpdatesOnboarding => 'Activer les versions bêta';

  @override
  String get betaUpdatesNote =>
      'Recevoir les préversions (bêta) quand elles sont disponibles.';

  @override
  String get supportAnnasArchive => 'Soutenir Anna\'s Archive';

  @override
  String get donationPitch =>
      'Faire un don à Anna\'s Archive permet des téléchargements plus rapides et les aide à maintenir le service pour tous. Vous pouvez saisir votre clé secrète ci-dessous.';

  @override
  String get annasSecretKey => 'Clé secrète Anna\'s Archive';

  @override
  String get supportThisApp => 'Soutenir cette application';

  @override
  String get sponsorPitch =>
      'Si vous aimez cette application, pensez à soutenir son développement. Cela m\'aide à y consacrer plus de temps !';

  @override
  String get sponsorOnGithub => 'Sponsoriser sur GitHub';

  @override
  String get stayUpdated => 'Rester informé';

  @override
  String get notifyOnComplete =>
      'Être notifié lorsque les téléchargements se terminent.';

  @override
  String get chooseTheme => 'Choisir un thème';

  @override
  String get lightThemeShort => 'Clair';

  @override
  String get darkThemeShort => 'Sombre';

  @override
  String get verifyingAccess => 'Vérification de l\'accès';

  @override
  String get done => 'Terminé';

  @override
  String get nothingToRead => 'Rien à lire sur cette page';

  @override
  String get noVoiceAvailable =>
      'Aucune voix disponible pour la lecture à voix haute';

  @override
  String get pauseReadingAloud => 'Mettre la lecture en pause';

  @override
  String get resumeReadingAloud => 'Lire à voix haute';

  @override
  String get stopReadingAloud => 'Arrêter la lecture';

  @override
  String get speechSpeed => 'Vitesse de la voix';

  @override
  String get decreaseFontSize => 'Réduire la taille de police';

  @override
  String get increaseFontSize => 'Augmenter la taille de police';

  @override
  String get close => 'Fermer';

  @override
  String get sortLibrary => 'Trier la bibliothèque';

  @override
  String get reloadHealthData => 'Recharger les données de santé';

  @override
  String addServiceMirror(String title) {
    return 'Ajouter un miroir $title';
  }

  @override
  String get deleteMirrorTooltip => 'Supprimer le miroir';
}
