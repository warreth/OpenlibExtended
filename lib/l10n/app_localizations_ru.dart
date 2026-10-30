// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'OpenlibExtended';

  @override
  String get navHome => 'Главная';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navMyLibrary => 'Моя библиотека';

  @override
  String get navSettings => 'Настройки';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get add => 'Добавить';

  @override
  String get delete => 'Удалить';

  @override
  String get retry => 'Повторить';

  @override
  String get advancedSearch => 'Расширенный поиск';

  @override
  String get author => 'Автор';

  @override
  String get publisher => 'Издатель';

  @override
  String get searchLibraryHint =>
      'Поиск по библиотеке (название, автор, издатель, год)';

  @override
  String get newCollection => 'Новая коллекция';

  @override
  String get noResultsFound => 'Ничего не найдено';

  @override
  String resultsFor(String query) {
    return 'Результаты по запросу «$query»';
  }

  @override
  String get followSystem => 'Как в системе';

  @override
  String get lightTheme => 'Светлая тема';

  @override
  String get darkTheme => 'Тёмная тема';

  @override
  String get languageSetting => 'Язык';

  @override
  String get systemLanguage => 'Системный по умолчанию';

  @override
  String get enableNotifications => 'Включить уведомления';

  @override
  String get notificationsExplanation =>
      'OpenlibExtended нужен доступ к уведомлениям, чтобы показывать прогресс загрузки в фоне. Так вы сможете следить за загрузкой книг, даже когда приложение свёрнуто.';

  @override
  String get maybeLater => 'Позже';

  @override
  String get enable => 'Включить';

  @override
  String get statusUnread => 'Не прочитано';

  @override
  String get statusInProgress => 'В процессе';

  @override
  String get statusCompleted => 'Прочитано';

  @override
  String get collectionNameHint => 'например, Избранное, Фантастика';

  @override
  String get manageCollectionsHint =>
      'Нажмите и удерживайте книгу, чтобы управлять её коллекциями';

  @override
  String get results => 'Результаты';

  @override
  String get loading => 'Загрузка...';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get about => 'О приложении';

  @override
  String get aboutDescription =>
      'Приложение с открытым исходным кодом для скачивания и чтения книг из теневых библиотек (Anna\'s Archive).';

  @override
  String get aboutForkNote =>
      'Это форк, который warreth поддерживает для личного использования и обновлений сообщества.';

  @override
  String get aboutOriginalNote =>
      'Оригинальное приложение от dstark5 (https://github.com/dstark5/Openlib).';

  @override
  String get version => 'Версия';

  @override
  String get github => 'Github';

  @override
  String get thisForkByWarreth => 'Этот форк (от warreth)';

  @override
  String get reportAnIssue => 'Сообщить о проблеме';

  @override
  String get originalProject => 'Оригинальный проект (от dstark5)';

  @override
  String get licence => 'Лицензия';

  @override
  String get gplLicense => 'Лицензия GPL v3.0';

  @override
  String couldNotLaunch(String url) {
    return 'Не удалось открыть $url';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get searchProvidersSection => 'Источники поиска';

  @override
  String get libraryInstancesSection => 'Библиотека и экземпляры';

  @override
  String get appearanceSection => 'Внешний вид';

  @override
  String get generalSection => 'Общие';

  @override
  String get readerSection => 'Читалка';

  @override
  String get advancedSection => 'Дополнительно';

  @override
  String get backupSection => 'Резервная копия';

  @override
  String get updatesSection => 'Обновления';

  @override
  String get aboutSection => 'О приложении';

  @override
  String get archiveInstance => 'Экземпляр архива';

  @override
  String get mirrorsAndProviders => 'Зеркала и источники';

  @override
  String get fontSizeTitle => 'Размер шрифта';

  @override
  String scaleValue(String value) {
    return 'Масштаб: ${value}x';
  }

  @override
  String get preview => 'Предпросмотр';

  @override
  String get storageLocation => 'Место хранения';

  @override
  String get openPdfExternally => 'Открывать PDF во внешней программе';

  @override
  String get useDefaultPdfViewer =>
      'Использовать программу просмотра PDF по умолчанию';

  @override
  String get openEpubExternally => 'Открывать EPUB во внешней программе';

  @override
  String get useDefaultEpubReader =>
      'Использовать программу чтения EPUB по умолчанию';

  @override
  String get manualDownloadButton => 'Кнопка ручной загрузки';

  @override
  String get backgroundVerification => 'Проверять задания в фоне';

  @override
  String get backgroundVerificationHint =>
      'Решать проверки DDoS незаметно. На некоторых устройствах это не работает — отключите, чтобы проходить проверку в видимом окне';

  @override
  String get backgroundVerificationFix =>
      'Если проверка продолжает сбоить, попробуйте отключить «Проверять задания в фоне» в настройках — некоторые устройства не могут решать проверки незаметно.';

  @override
  String get showManualDownloadHint =>
      'Показывать кнопку для ручного запуска загрузки';

  @override
  String get donationKeyTitle => 'Ключ поддержки Anna\'s Archive';

  @override
  String get enterKeyForFasterDownloads =>
      'Введите ключ для более быстрых загрузок';

  @override
  String get aboutOpenlib => 'Об OpenlibExtended';

  @override
  String get redoOnboarding => 'Пройти первоначальную настройку заново';

  @override
  String get resetAppSetup => 'Сбросить настройки приложения и начать заново';

  @override
  String get exportLogs => 'Экспорт журналов';

  @override
  String get shareDiagnosticLogs =>
      'Поделиться диагностическими журналами (последние 5 мин)';

  @override
  String failedExportLogs(String error) {
    return 'Не удалось экспортировать журналы: $error';
  }

  @override
  String get donationKeyDialog => 'Ключ поддержки';

  @override
  String get enterYourKey => 'Введите ключ';

  @override
  String get instanceChanged => 'Экземпляр успешно изменён';

  @override
  String rankingFailed(String error) {
    return 'Не удалось выполнить ранжирование: $error';
  }

  @override
  String get autoRankInstances => 'Автоматически ранжировать экземпляры';

  @override
  String get sortBySpeedOnStartup => 'Сортировать по скорости при запуске';

  @override
  String get rankInstancesNow => 'Ранжировать экземпляры сейчас';

  @override
  String onLatestVersion(String version) {
    return 'У вас последняя версия ($version)';
  }

  @override
  String failedCheckUpdates(String error) {
    return 'Не удалось проверить обновления: $error';
  }

  @override
  String get includeBetaUpdates => 'Включать бета-обновления';

  @override
  String get getPreReleaseVersions => 'Получать предварительные версии';

  @override
  String get checkForUpdates => 'Проверить обновления';

  @override
  String get backupSaved => 'Резервная копия сохранена';

  @override
  String failedExportBackup(String error) {
    return 'Не удалось экспортировать резервную копию: $error';
  }

  @override
  String get backupRestored => 'Резервная копия восстановлена';

  @override
  String failedImportBackup(String error) {
    return 'Не удалось импортировать резервную копию: $error';
  }

  @override
  String get atLeastOneSource => 'Нужен хотя бы один источник поиска';

  @override
  String rankedFastest(String name, String time) {
    return 'Готово! Самый быстрый: $name ($time мс)';
  }

  @override
  String get rankingComplete => 'Ранжирование завершено';

  @override
  String get providerSourceOriginal => 'Ищется последним — защищено DDoS-Guard';

  @override
  String get providerLibgenCatalog => 'Быстрые прямые загрузки — ищется первым';

  @override
  String get providerZlibMirrors =>
      'Зеркала меняются; может потребоваться вход';

  @override
  String get themeTitle => 'Тема';

  @override
  String get saveBackupTitle => 'Сохранить резервную копию';

  @override
  String get pickBackupFile => 'Выберите файл резервной копии';

  @override
  String get notABackup =>
      'Этот файл не является резервной копией OpenlibExtended';

  @override
  String get donationKeyHelper =>
      'Используется для более быстрых загрузок на Anna\'s Archive';

  @override
  String get mirrorsTestedRanked =>
      'Зеркала проверены и отсортированы по скорости';

  @override
  String testingFailed(String error) {
    return 'Проверка не удалась: $error';
  }

  @override
  String get addCustomMirror => 'Добавить своё зеркало';

  @override
  String get nameLabel => 'Название';

  @override
  String get nameHint => 'например, моё зеркало LibGen';

  @override
  String get serviceLabel => 'Сервис';

  @override
  String get urlLabel => 'URL';

  @override
  String get urlHint => 'https://example.com';

  @override
  String get pleaseFillAllFields => 'Заполните все поля';

  @override
  String get enterValidUrl => 'Введите корректный URL с http:// или https://';

  @override
  String get mirrorAdded => 'Зеркало успешно добавлено';

  @override
  String get deleteMirror => 'Удалить зеркало';

  @override
  String deleteMirrorConfirm(String name) {
    return 'Вы уверены, что хотите удалить «$name»?';
  }

  @override
  String get mirrorDeleted => 'Зеркало удалено';

  @override
  String get cannotDeleteDefaultMirrors => 'Нельзя удалить стандартные зеркала';

  @override
  String get manageMirrors => 'Управление зеркалами';

  @override
  String get noMirrorsAvailable => 'Нет доступных зеркал';

  @override
  String errorLabel(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get addMirror => 'Добавить зеркало';

  @override
  String get testRankMirrors => 'Проверить и отсортировать зеркала по скорости';

  @override
  String get unreachable => 'недоступно';

  @override
  String get open => 'Открыть';

  @override
  String get unableToOpenFile => 'Не удалось открыть файл!';

  @override
  String get openInSite => 'Открыть на сайте';

  @override
  String get bookDeleted => 'Книга удалена!';

  @override
  String get deleteBook => 'Удалить книгу';

  @override
  String get deletePermanentWarning => 'Это действие необратимо';

  @override
  String get tryAgain => 'Повторить';

  @override
  String get showBlockedContent =>
      'Показать содержимое заблокированной страницы';

  @override
  String get verifyInBrowser => 'Проверить в браузере';

  @override
  String get manualVerificationRequired => 'Требуется ручная проверка';

  @override
  String get systemBrowser => 'Системный браузер';

  @override
  String get embeddedBrowser => 'Встроенный браузер';

  @override
  String get unableToOpenVerification =>
      'Не удалось открыть страницу проверки — URL недоступен';

  @override
  String get blockedPageContent => 'Содержимое заблокированной страницы';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get gotIt => 'Понятно!';

  @override
  String get copy => 'Копировать';

  @override
  String get tryUsingVpn => 'Попробуйте VPN';

  @override
  String get trending => 'Популярное';

  @override
  String get genres => 'Жанры';

  @override
  String get copiedBookPath => 'Путь к книге скопирован в буфер обмена';

  @override
  String get pauseDownload => 'Приостановить загрузку';

  @override
  String get resumeDownload => 'Продолжить загрузку';

  @override
  String get cancelDownload => 'Отменить загрузку';

  @override
  String get copiedBookLink => 'Ссылка на книгу скопирована в буфер обмена';

  @override
  String get noMirrors => 'Нет доступных зеркал!';

  @override
  String get addToMyLibrary => 'Добавить в мою библиотеку';

  @override
  String get downloadStartedBackground => 'Загрузка началась в фоне';

  @override
  String get bookDownloaded => 'Книга загружена!';

  @override
  String get selectStorageToContinue =>
      'Выберите папку для хранения, чтобы продолжить';

  @override
  String get getStarted => 'Начать';

  @override
  String get next => 'Далее';

  @override
  String get welcomeTitle => 'Добро пожаловать в OpenlibExtended';

  @override
  String get welcomeSubtitle =>
      'Ваш личный портал в мир знаний. Давайте всё настроим.';

  @override
  String get whereToStoreBooks => 'Где хранить ваши книги?';

  @override
  String get noPathSelected => 'Путь не выбран';

  @override
  String get selectFolder => 'Выбрать папку';

  @override
  String get storageScanNote =>
      'Мы будем искать только файлы PDF/EPUB в этой папке. Подпапки не сканируются.';

  @override
  String get automaticUpdates => 'Автоматические обновления';

  @override
  String get enableAutoUpdates => 'Включить автообновления';

  @override
  String get autoUpdatesFdroidNote =>
      'Не рекомендуется при установке через F-Droid (F-Droid сам управляет обновлениями).';

  @override
  String get enableBetaUpdatesOnboarding => 'Включить бета-обновления';

  @override
  String get betaUpdatesNote =>
      'Получать предварительные версии (бета-обновления), когда они доступны.';

  @override
  String get supportAnnasArchive => 'Поддержать Anna\'s Archive';

  @override
  String get donationPitch =>
      'Пожертвования Anna\'s Archive ускоряют загрузки и помогают поддерживать сервис для всех. Ниже можно ввести секретный ключ.';

  @override
  String get annasSecretKey => 'Секретный ключ Anna\'s Archive';

  @override
  String get supportThisApp => 'Поддержать это приложение';

  @override
  String get sponsorPitch =>
      'Если вам нравится приложение, подумайте о поддержке его разработки. Это поможет мне уделять ему больше времени!';

  @override
  String get sponsorOnGithub => 'Поддержать на GitHub';

  @override
  String get stayUpdated => 'Будьте в курсе';

  @override
  String get notifyOnComplete => 'Получать уведомления о завершении загрузок.';

  @override
  String get chooseTheme => 'Выберите тему';

  @override
  String get lightThemeShort => 'Светлая';

  @override
  String get darkThemeShort => 'Тёмная';

  @override
  String get verifyingAccess => 'Проверка доступа';

  @override
  String get done => 'Готово';

  @override
  String get nothingToRead => 'На этой странице нечего читать';

  @override
  String get noVoiceAvailable => 'Нет голоса для чтения вслух';

  @override
  String get pauseReadingAloud => 'Приостановить чтение вслух';

  @override
  String get resumeReadingAloud => 'Читать вслух';

  @override
  String get stopReadingAloud => 'Остановить чтение вслух';

  @override
  String get speechSpeed => 'Скорость речи';

  @override
  String get decreaseFontSize => 'Уменьшить размер шрифта';

  @override
  String get increaseFontSize => 'Увеличить размер шрифта';

  @override
  String get close => 'Закрыть';

  @override
  String get sortLibrary => 'Сортировать библиотеку';

  @override
  String get reloadHealthData => 'Обновить данные о состоянии';

  @override
  String addServiceMirror(String title) {
    return 'Добавить зеркало $title';
  }

  @override
  String get deleteMirrorTooltip => 'Удалить зеркало';

  @override
  String get ttsEngineMissing =>
      'Синтезатор речи не найден. Установите его (например, Speech Services) в настройках системы.';

  @override
  String get previousPage => 'Предыдущая страница';

  @override
  String get nextPage => 'Следующая страница';

  @override
  String searchingOn(String source) {
    return 'Результаты от $source';
  }

  @override
  String get sourceLibgen => 'LibGen';

  @override
  String get sourceZlib => 'Z-Library';

  @override
  String get sourceAnnas => 'Anna\'s Archive';

  @override
  String downloadFrom(String source) {
    return 'Загрузка с $source';
  }

  @override
  String get tryingNextSource =>
      'Здесь ничего не найдено, пробуем следующий источник…';

  @override
  String get slowMirrorsSkipped => 'Используются более быстрые зеркала';

  @override
  String whatsNewTitle(String version) {
    return 'Что нового в $version';
  }

  @override
  String get whatsNewIntro => 'OpenlibExtended обновлено. Вот что изменилось.';

  @override
  String get whatsNewTabFeatures => 'Новые функции';

  @override
  String get whatsNewTabSources => 'Источники и зеркала';

  @override
  String get whatsNewProvidersHint =>
      'В этом выпуске добавлены новые источники поиска и зеркала. Обновите список, чтобы убрать неработающие зеркала и добавить новые; все три источника поиска будут включены.';

  @override
  String get whatsNewUpdateInstances => 'Обновить список зеркал';

  @override
  String get whatsNewInstancesUpdated => 'Список зеркал обновлён';

  @override
  String get whatsNewContinue => 'Продолжить';

  @override
  String get whatsNewFeatureSpeed =>
      'Загрузки начинаются быстрее: без проверки зеркал, сначала быстрые хосты, медленные шлюзы IPFS в конце.';

  @override
  String get whatsNewFeatureSourceLabels =>
      'Теперь у каждого результата поиска и загрузки видно, из какого каталога он получен.';

  @override
  String get whatsNewFeatureCovers =>
      'Недостающие обложки LibGen загружаются со страницы книги.';
}
