// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'Inicio';

  @override
  String get navSearch => 'Buscar';

  @override
  String get navMyLibrary => 'Mi biblioteca';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get add => 'Añadir';

  @override
  String get delete => 'Eliminar';

  @override
  String get retry => 'Reintentar';

  @override
  String get advancedSearch => 'Búsqueda avanzada';

  @override
  String get author => 'Autor';

  @override
  String get publisher => 'Editorial';

  @override
  String get searchLibraryHint =>
      'Buscar en la biblioteca (título, autor, editorial, año)';

  @override
  String get newCollection => 'Nueva colección';

  @override
  String get noResultsFound => 'No se encontraron resultados';

  @override
  String resultsFor(String query) {
    return 'Resultados para «$query»';
  }

  @override
  String get followSystem => 'Seguir el sistema';

  @override
  String get lightTheme => 'Tema claro';

  @override
  String get darkTheme => 'Tema oscuro';

  @override
  String get languageSetting => 'Idioma';

  @override
  String get systemLanguage => 'Idioma del sistema';

  @override
  String get enableNotifications => 'Activar notificaciones';

  @override
  String get notificationsExplanation =>
      'OpenlibExtended necesita el permiso de notificaciones para mostrar el progreso de las descargas en segundo plano. Así puedes seguir tus descargas de libros aunque la aplicación esté minimizada.';

  @override
  String get maybeLater => 'Quizás más tarde';

  @override
  String get enable => 'Activar';

  @override
  String get statusUnread => 'Sin leer';

  @override
  String get statusInProgress => 'En progreso';

  @override
  String get statusCompleted => 'Completado';

  @override
  String get collectionNameHint => 'p. ej., Favoritos, Ciencia ficción';

  @override
  String get manageCollectionsHint =>
      'Mantén pulsado un libro para gestionar sus colecciones';

  @override
  String get results => 'Resultados';

  @override
  String get loading => 'Cargando...';

  @override
  String get unknown => 'Desconocido';

  @override
  String get about => 'Acerca de';

  @override
  String get aboutDescription =>
      'Una aplicación de código abierto para descargar y leer libros de bibliotecas en la sombra (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'Versión bifurcada mantenida por warreth para uso personal y actualizaciones de la comunidad.';

  @override
  String get aboutOriginalNote =>
      'Aplicación original de dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Versión';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'Este fork (por warreth)';

  @override
  String get reportAnIssue => 'Informar de un problema';

  @override
  String get originalProject => 'Proyecto original (por dstark5)';

  @override
  String get licence => 'Licencia';

  @override
  String get gplLicense => 'Licencia GPL v3.0';

  @override
  String couldNotLaunch(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get searchProvidersSection => 'Fuentes de búsqueda';

  @override
  String get libraryInstancesSection => 'Biblioteca e instancias';

  @override
  String get appearanceSection => 'Apariencia';

  @override
  String get generalSection => 'General';

  @override
  String get readerSection => 'Lector';

  @override
  String get advancedSection => 'Avanzado';

  @override
  String get backupSection => 'Copia de seguridad';

  @override
  String get updatesSection => 'Actualizaciones';

  @override
  String get aboutSection => 'Acerca de';

  @override
  String get archiveInstance => 'Instancia de archivo';

  @override
  String get mirrorsAndProviders => 'Espejos y fuentes';

  @override
  String get fontSizeTitle => 'Tamaño de letra';

  @override
  String scaleValue(String value) {
    return 'Escala: ${value}x';
  }

  @override
  String get preview => 'Vista previa';

  @override
  String get storageLocation => 'Ubicación de almacenamiento';

  @override
  String get openPdfExternally => 'Abrir PDF externamente';

  @override
  String get useDefaultPdfViewer => 'Usar tu visor PDF predeterminado';

  @override
  String get openEpubExternally => 'Abrir EPUB externamente';

  @override
  String get useDefaultEpubReader => 'Usar tu lector EPUB predeterminado';

  @override
  String get manualDownloadButton => 'Botón de descarga manual';

  @override
  String get backgroundVerification => 'Verificar en segundo plano';

  @override
  String get backgroundVerificationHint =>
      'Resuelve comprobaciones DDoS de forma invisible. En algunos dispositivos falla - desactívalo para verificar en una ventana visible';

  @override
  String get backgroundVerificationFix =>
      'Si la verificación sigue fallando, desactiva \"Verificar en segundo plano\" en Ajustes: algunos dispositivos no pueden resolver comprobaciones de forma invisible.';

  @override
  String get showManualDownloadHint =>
      'Mostrar botón para iniciar descargas manualmente';

  @override
  String get donationKeyTitle => 'Clave de donación de Anna\'s Archive';

  @override
  String get enterKeyForFasterDownloads =>
      'Introduce la clave para descargas más rápidas';

  @override
  String get aboutOpenlib => 'Acerca de OpenlibExtended';

  @override
  String get redoOnboarding => 'Repetir la introducción';

  @override
  String get resetAppSetup => 'Restablecer la configuración y empezar de nuevo';

  @override
  String get exportLogs => 'Exportar registros';

  @override
  String get shareDiagnosticLogs =>
      'Compartir registros de diagnóstico (últimos 5 min)';

  @override
  String failedExportLogs(String error) {
    return 'Error al exportar registros: $error';
  }

  @override
  String get donationKeyDialog => 'Clave de donación';

  @override
  String get enterYourKey => 'Introduce tu clave';

  @override
  String get instanceChanged => 'Instancia cambiada correctamente';

  @override
  String rankingFailed(String error) {
    return 'Error al clasificar: $error';
  }

  @override
  String get autoRankInstances => 'Clasificar instancias automáticamente';

  @override
  String get sortBySpeedOnStartup =>
      'Ordenar automáticamente por velocidad al iniciar';

  @override
  String get rankInstancesNow => 'Clasificar instancias ahora';

  @override
  String onLatestVersion(String version) {
    return 'Ya tienes la última versión ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Error al buscar actualizaciones: $error';
  }

  @override
  String get includeBetaUpdates => 'Incluir versiones beta';

  @override
  String get getPreReleaseVersions => 'Obtener versiones preliminares';

  @override
  String get checkForUpdates => 'Buscar actualizaciones';

  @override
  String get backupSaved => 'Copia de seguridad guardada';

  @override
  String failedExportBackup(String error) {
    return 'Error al exportar la copia: $error';
  }

  @override
  String get backupRestored => 'Copia de seguridad restaurada';

  @override
  String failedImportBackup(String error) {
    return 'Error al importar la copia: $error';
  }

  @override
  String get atLeastOneSource => 'Se necesita al menos una fuente de búsqueda';

  @override
  String rankedFastest(String name, String time) {
    return '¡Clasificado! Más rápida: $name (${time}ms)';
  }

  @override
  String get rankingComplete => 'Clasificación completada';

  @override
  String get providerSourceOriginal =>
      'Se busca al final - protegido por DDoS-Guard';

  @override
  String get providerLibgenCatalog =>
      'Descargas rápidas y directas - se busca primero';

  @override
  String get providerZlibMirrors =>
      'Los espejos rotan; puede requerir inicio de sesión';

  @override
  String get themeTitle => 'Tema';

  @override
  String get saveBackupTitle => 'Guardar copia de seguridad';

  @override
  String get pickBackupFile => 'Elegir un archivo de copia';

  @override
  String get notABackup =>
      'Ese archivo no es una copia de seguridad de OpenlibExtended';

  @override
  String get donationKeyHelper =>
      'Se usa para descargas más rápidas en Anna\'s Archive';

  @override
  String get mirrorsTestedRanked =>
      'Espejos probados y clasificados por velocidad';

  @override
  String testingFailed(String error) {
    return 'Error al probar: $error';
  }

  @override
  String get addCustomMirror => 'Añadir espejo personalizado';

  @override
  String get nameLabel => 'Nombre';

  @override
  String get nameHint => 'p. ej., Mi espejo de LibGen';

  @override
  String get serviceLabel => 'Servicio';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Rellena todos los campos';

  @override
  String get enterValidUrl => 'Introduce una URL válida con http:// o https://';

  @override
  String get mirrorAdded => 'Espejo añadido correctamente';

  @override
  String get deleteMirror => 'Eliminar espejo';

  @override
  String deleteMirrorConfirm(String name) {
    return '¿Seguro que quieres eliminar «$name»?';
  }

  @override
  String get mirrorDeleted => 'Espejo eliminado';

  @override
  String get cannotDeleteDefaultMirrors =>
      'No se pueden eliminar los espejos predeterminados';

  @override
  String get manageMirrors => 'Gestionar espejos';

  @override
  String get noMirrorsAvailable => 'No hay espejos disponibles';

  @override
  String errorLabel(String error) {
    return 'Error: $error';
  }

  @override
  String get addMirror => 'Añadir espejo';

  @override
  String get testRankMirrors => 'Probar y clasificar espejos por velocidad';

  @override
  String get unreachable => 'inaccesible';

  @override
  String get open => 'Abrir';

  @override
  String get unableToOpenFile => '¡No se pudo abrir el archivo!';

  @override
  String get openInSite => 'Abrir en el sitio';

  @override
  String get bookDeleted => '¡Libro eliminado!';

  @override
  String get deleteBook => 'Eliminar libro';

  @override
  String get deletePermanentWarning =>
      'Esto es permanente y no se puede deshacer';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get showBlockedContent => 'Mostrar contenido de la página bloqueada';

  @override
  String get verifyInBrowser => 'Verificar en el navegador';

  @override
  String get manualVerificationRequired => 'Verificación manual requerida';

  @override
  String get systemBrowser => 'Navegador del sistema';

  @override
  String get embeddedBrowser => 'Navegador integrado';

  @override
  String get unableToOpenVerification =>
      'No se pudo abrir la página de verificación - no hay URL disponible';

  @override
  String get blockedPageContent => 'Contenido de la página bloqueada';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get gotIt => '¡Entendido!';

  @override
  String get copy => 'Copiar';

  @override
  String get tryUsingVpn => 'Prueba a usar una VPN';

  @override
  String get trending => 'Tendencias';

  @override
  String get genres => 'Géneros';

  @override
  String get copiedBookPath => 'Ruta del libro copiada al portapapeles';

  @override
  String get pauseDownload => 'Pausar descarga';

  @override
  String get resumeDownload => 'Reanudar descarga';

  @override
  String get cancelDownload => 'Cancelar descarga';

  @override
  String get copiedBookLink => 'Enlace del libro copiado al portapapeles';

  @override
  String get noMirrors => '¡No hay espejos disponibles!';

  @override
  String get addToMyLibrary => 'Añadir a mi biblioteca';

  @override
  String get downloadStartedBackground => 'Descarga iniciada en segundo plano';

  @override
  String get bookDownloaded => '¡Libro descargado!';

  @override
  String get selectStorageToContinue =>
      'Selecciona una carpeta de almacenamiento para continuar';

  @override
  String get getStarted => 'Comenzar';

  @override
  String get next => 'Siguiente';

  @override
  String get welcomeTitle => 'Bienvenido a OpenlibExtended';

  @override
  String get welcomeSubtitle =>
      'Tu puerta de entrada personal a un mundo de conocimiento. Vamos a configurarlo todo.';

  @override
  String get whereToStoreBooks => '¿Dónde guardamos tus libros?';

  @override
  String get noPathSelected => 'Ninguna ruta seleccionada';

  @override
  String get selectFolder => 'Elegir carpeta';

  @override
  String get storageScanNote =>
      'Solo buscaremos archivos PDF/EPUB en esta carpeta. No se escanean subcarpetas.';

  @override
  String get automaticUpdates => 'Actualizaciones automáticas';

  @override
  String get enableAutoUpdates => 'Activar actualizaciones automáticas';

  @override
  String get autoUpdatesFdroidNote =>
      'No se recomienda si instalaste desde F-Droid (F-Droid gestiona las actualizaciones).';

  @override
  String get enableBetaUpdatesOnboarding => 'Activar versiones beta';

  @override
  String get betaUpdatesNote =>
      'Recibir versiones preliminares (beta) cuando estén disponibles.';

  @override
  String get supportAnnasArchive => 'Apoyar a Anna\'s Archive';

  @override
  String get donationPitch =>
      'Donar a Anna\'s Archive permite descargas más rápidas y les ayuda a mantener el servicio para todos. Puedes introducir tu clave secreta abajo.';

  @override
  String get annasSecretKey => 'Clave secreta de Anna\'s Archive';

  @override
  String get supportThisApp => 'Apoyar esta aplicación';

  @override
  String get sponsorPitch =>
      'Si te gusta esta aplicación, considera apoyar su desarrollo. ¡Me ayuda a dedicar más tiempo a mejorarla!';

  @override
  String get sponsorOnGithub => 'Patrocinar en GitHub';

  @override
  String get stayUpdated => 'Mantente al día';

  @override
  String get notifyOnComplete => 'Recibir aviso cuando terminen las descargas.';

  @override
  String get chooseTheme => 'Elige un tema';

  @override
  String get lightThemeShort => 'Claro';

  @override
  String get darkThemeShort => 'Oscuro';

  @override
  String get verifyingAccess => 'Verificando acceso';

  @override
  String get done => 'Hecho';

  @override
  String get nothingToRead => 'Nada que leer en esta página';

  @override
  String get noVoiceAvailable => 'No hay voz disponible para leer en voz alta';

  @override
  String get pauseReadingAloud => 'Pausar lectura en voz alta';

  @override
  String get resumeReadingAloud => 'Leer en voz alta';

  @override
  String get stopReadingAloud => 'Detener lectura en voz alta';

  @override
  String get speechSpeed => 'Velocidad del habla';

  @override
  String get decreaseFontSize => 'Reducir tamaño de letra';

  @override
  String get increaseFontSize => 'Aumentar tamaño de letra';

  @override
  String get close => 'Cerrar';

  @override
  String get sortLibrary => 'Ordenar biblioteca';

  @override
  String get reloadHealthData => 'Recargar datos de salud';

  @override
  String addServiceMirror(String title) {
    return 'Añadir un espejo de $title';
  }

  @override
  String get deleteMirrorTooltip => 'Eliminar espejo';

  @override
  String get ttsEngineMissing =>
      'No se encontró ningún motor de síntesis de voz. Instala uno (p. ej. Servicios de voz) en los ajustes del sistema.';
}
