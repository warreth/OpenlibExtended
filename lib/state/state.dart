// Dart imports:
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
// NOTE: These imports are crucial and must exist in your project structure.
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart';
import 'package:openlib/services/open_library.dart';
import 'package:openlib/services/goodreads.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/download_manager.dart';
// Assuming OpenLibrary, Goodreads, PenguinRandomHouse, BookDigits, and SubCategoriesTypeList are defined
// or are simple placeholder services/models that work as intended.

MyLibraryDb dataBase = MyLibraryDb.instance;

// ====================================================================
// DROPDOWN/FILTER MAPPING DATA
// ====================================================================

Map<String, String> typeValues = {
  'All': '',
  'Any Books': 'book_any',
  'Unknown Books': 'book_unknown',
  'Fiction Books': 'book_fiction',
  'Non-fiction Books': 'book_nonfiction',
  'Comic Books': 'book_comic',
  'Magazine': 'magazine',
  'Standards Document': 'standards_document',
  'Journal Article': 'journal_article'
};

Map<String, String> sortValues = {
  'Most Relevant': '',
  'Newest': 'newest',
  'Oldest': 'oldest',
  'Largest': 'largest',
  'Smallest': 'smallest',
};

List<String> fileType = ["All", "PDF", "Epub", "Cbr", "Cbz"];

// Language filter values (display name: code)
Map<String, String> languageValues = {
  "All": "",
  "English": "en",
  "Spanish": "es",
  "French": "fr",
  "German": "de",
  "Italian": "it",
  "Portuguese": "pt",
  "Russian": "ru",
  "Chinese": "zh",
  "Japanese": "ja",
  "Korean": "ko",
  "Arabic": "ar",
  "Hindi": "hi",
  "Malayalam": "ml",
  "Dutch": "nl",
  "Polish": "pl",
  "Turkish": "tr",
  "Swedish": "sv",
  "Indonesian": "id",
  "Vietnamese": "vi",
  "Czech": "cs",
  "Greek": "el",
  "Romanian": "ro",
  "Hungarian": "hu",
  "Ukrainian": "uk",
  "Hebrew": "he",
  "Thai": "th",
  "Persian": "fa",
  "Bengali": "bn",
  "Finnish": "fi",
  "Norwegian": "no",
  "Danish": "da",
};

// Reverse map: language code to uppercase display code
Map<String, String> languageCodeToDisplay = {
  "en": "EN",
  "es": "ES",
  "fr": "FR",
  "de": "DE",
  "it": "IT",
  "pt": "PT",
  "ru": "RU",
  "zh": "ZH",
  "ja": "JA",
  "ko": "KO",
  "ar": "AR",
  "hi": "HI",
  "ml": "ML",
  "nl": "NL",
  "pl": "PL",
  "tr": "TR",
  "sv": "SV",
  "id": "ID",
  "vi": "VI",
  "cs": "CS",
  "el": "EL",
  "ro": "RO",
  "hu": "HU",
  "uk": "UK",
  "he": "HE",
  "th": "TH",
  "fa": "FA",
  "bn": "BN",
  "fi": "FI",
  "no": "NO",
  "da": "DA",
};

// Year filter values for publishing year range
List<String> yearValues = [
  "All",
  "2025",
  "2024",
  "2023",
  "2022",
  "2021",
  "2020",
  "2019",
  "2018",
  "2017",
  "2016",
  "2015",
  "2010-2014",
  "2005-2009",
  "2000-2004",
  "1990-1999",
  "1980-1989",
  "Before 1980",
];

// ====================================================================
// ENUMS AND DATA CLASSES
// ====================================================================

enum ProcessState { waiting, running, complete }

enum CheckSumProcessState { waiting, running, failed, success }

class FileName {
  final String md5;
  final String format;
  final String? fileName;

  FileName({required this.md5, required this.format, this.fileName});
}

// ====================================================================
// UI AND SIMPLE STATE PROVIDERS
// ====================================================================

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(super.state);

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;

    // Save to DB
    String pref = 'system';
    if (mode == ThemeMode.light) pref = 'light';
    if (mode == ThemeMode.dark) pref = 'dark';
    await MyLibraryDb.instance.savePreference('themeMode', pref);

    updateSystemUi(mode);
  }

  static void updateSystemUi(ThemeMode mode) {
    if (Platform.isAndroid) {
      bool isDark = mode == ThemeMode.dark;
      if (mode == ThemeMode.system) {
        isDark = ui.PlatformDispatcher.instance.platformBrightness ==
            Brightness.dark;
      }
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          systemNavigationBarColor:
              isDark ? Colors.black : Colors.grey.shade200));
    }
  }

  static Future<ThemeMode> getInitialTheme() async {
    try {
      MyLibraryDb dataBase = MyLibraryDb.instance;
      // Check for new theme mode preference
      var themePref =
          await dataBase.getPreference('themeMode').catchError((e) => null);
      if (themePref != null && themePref is String) {
        if (themePref == 'light') return ThemeMode.light;
        if (themePref == 'dark') return ThemeMode.dark;
        return ThemeMode.system;
      } else {
        // Fallback to legacy darkMode preference
        var legacyDark =
            await dataBase.getPreference('darkMode').catchError((e) => null);
        if (legacyDark != null) {
          return (legacyDark == 0) ? ThemeMode.light : ThemeMode.dark;
        }
      }
    } catch (e) {
      // Ignore
    }
    return ThemeMode.system;
  }
}

final selectedIndexProvider = StateProvider<int>((ref) => 0);
final homePageSelectedIndexProvider = StateProvider<int>((ref) => 0);
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ThemeMode.light);
});
final fontSizeScaleProvider = StateProvider<double>((ref) => 1.0);

// Search Filter States
final selectedTypeState = StateProvider<String>((ref) => "All");
final selectedSortState = StateProvider<String>((ref) => "Most Relevant");
final selectedFileTypeState = StateProvider<String>((ref) => "All");
final selectedLanguageState = StateProvider<String>((ref) => "All");
final selectedYearState = StateProvider<String>((ref) => "All");
final searchQueryProvider = StateProvider<String>((ref) => "");
final enableFiltersState = StateProvider<bool>((ref) => true);

// Web/Download States
final donationKeyProvider = StateProvider<String>((ref) => "");
final cookieProvider = StateProvider<String>((ref) => "");
final userAgentProvider = StateProvider<String>((ref) => "");
final webViewLoadingState = StateProvider.autoDispose<bool>((ref) => true);
final downloadProgressProvider =
    StateProvider.autoDispose<double>((ref) => 0.0);
final mirrorStatusProvider = StateProvider.autoDispose<bool>((ref) => false);
final totalFileSizeInBytes = StateProvider.autoDispose<int>((ref) => 0);
final downloadedFileSizeInBytes = StateProvider.autoDispose<int>((ref) => 0);
final downloadState =
    StateProvider.autoDispose<ProcessState>((ref) => ProcessState.waiting);
final checkSumState = StateProvider.autoDispose<CheckSumProcessState>(
    (ref) => CheckSumProcessState.waiting);
final cancelCurrentDownload = StateProvider<CancelToken>((ref) {
  return CancelToken();
});

// PDF/Epub Reader States
final pdfCurrentPage = StateProvider.autoDispose<int>((ref) => 0);
final totalPdfPage = StateProvider.autoDispose<int>((ref) => 0);
final openPdfWithExternalAppProvider = StateProvider<bool>((ref) => false);
final openEpubWithExternalAppProvider = StateProvider<bool>((ref) => false);

// Download Settings
final showManualDownloadButtonProvider = StateProvider<bool>((ref) => false);

// Instance Auto-Ranking Setting (default: enabled)
final autoRankInstancesProvider = StateProvider<bool>((ref) => true);

// Instance Management States
final instanceManagerProvider =
    Provider<InstanceManager>((ref) => InstanceManager());

// Download Manager States
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

final activeDownloadsProvider =
    StreamProvider<Map<String, DownloadTask>>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  return manager.downloadsStream;
});

final archiveInstancesProvider =
    FutureProvider<List<ArchiveInstance>>((ref) async {
  final manager = ref.watch(instanceManagerProvider);
  return await manager.getInstances();
});

final enabledInstancesProvider =
    FutureProvider<List<ArchiveInstance>>((ref) async {
  final manager = ref.watch(instanceManagerProvider);
  return await manager.getEnabledInstances();
});

final currentInstanceProvider = FutureProvider<ArchiveInstance>((ref) async {
  final manager = ref.watch(instanceManagerProvider);
  return await manager.getCurrentInstance();
});

// ====================================================================
// DERIVED (COMPUTED) STATE PROVIDERS
// ====================================================================

final getTypeValue = Provider.autoDispose<String>((ref) {
  return typeValues[ref.watch(selectedTypeState)] ?? '';
});

final getSortValue = Provider.autoDispose<String>((ref) {
  return sortValues[ref.watch(selectedSortState)] ?? '';
});

final getFileTypeValue = Provider.autoDispose<String>((ref) {
  final selectedFile = ref.watch(selectedFileTypeState);
  return selectedFile == "All" ? '' : selectedFile.toLowerCase();
});

final getLanguageValue = Provider.autoDispose<String>((ref) {
  return languageValues[ref.watch(selectedLanguageState)] ?? '';
});

final getYearValue = Provider.autoDispose<String>((ref) {
  return ref.watch(selectedYearState) == "All"
      ? ''
      : ref.watch(selectedYearState);
});

// Helper function to convert bytes to readable file size
String bytesToFileSize(int bytes) {
  const int decimals = 1;
  const suffixes = ["b", " Kb", "Mb", "Gb", "Tb"];
  if (bytes == 0) return '0${suffixes[0]}';
  var i = (log(bytes) / log(1024)).floor();
  return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + suffixes[i];
}

final getTotalFileSize = StateProvider.autoDispose<String>((ref) {
  return bytesToFileSize(ref.watch(totalFileSizeInBytes));
});

final getDownloadedFileSize = StateProvider.autoDispose<String>((ref) {
  return bytesToFileSize(ref.watch(downloadedFileSizeInBytes));
});

// ====================================================================
// ASYNCHRONOUS DATA (FUTURE) PROVIDERS
// ====================================================================

// Provider for Trending Books
final getTrendingBooks = FutureProvider<List<TrendingBookData>>((ref) async {
  // NOTE: Assuming TrendingBookData and the service classes exist and are functional
  GoodReads goodReads = GoodReads();
  // Assuming these classes are available from your project imports
  // ignore: prefer_const_constructors
  final penguinTrending = PenguinRandomHouse();
  // ignore: prefer_const_constructors
  final bookDigits = BookDigits();

  List<TrendingBookData> trendingBooks =
      await Future.wait<List<TrendingBookData>>([
    goodReads.trendingBooks(),
    penguinTrending.trendingBooks(),
    // openLibrary.trendingBooks(), // Commented out as in the original
    bookDigits.trendingBooks(),
  ]).then((List<List<TrendingBookData>> listOfData) =>
          listOfData.expand((element) => element).toList());

  if (trendingBooks.isEmpty) {
    throw Exception(
        'Nothing Trending Today :('); // Use Exception instead of String
  }
  trendingBooks.shuffle();
  return trendingBooks;
});

// Provider for Sub Category Books
final getSubCategoryTypeList = FutureProvider.family
    .autoDispose<List<CategoryBookData>, String>((ref, url) async {
  // NOTE: Assuming CategoryBookData and SubCategoriesTypeList exist
  // ignore: prefer_const_constructors
  SubCategoriesTypeList subCategoriesTypeList = SubCategoriesTypeList();
  List<CategoryBookData> subCategories =
      await subCategoriesTypeList.categoriesBooks(url: url);
  List<CategoryBookData> uniqueArray = subCategories.toSet().toList();
  uniqueArray.shuffle();
  return uniqueArray;
});

// Provider for Anna's Archive Search Results
final searchProvider = FutureProvider.family
    .autoDispose<List<BookData>, String>((ref, searchQuery) async {
  if (searchQuery.isEmpty) {
    return []; // Return empty list if search query is empty
  }

  final AnnasArchieve annasArchieve = AnnasArchieve();
  List<BookData> data = await annasArchieve.searchBooks(
      searchQuery: searchQuery,
      content: ref.watch(getTypeValue),
      sort: ref.watch(getSortValue),
      fileType: ref.watch(getFileTypeValue),
      language: ref.watch(getLanguageValue),
      year: ref.watch(getYearValue),
      enableFilters: ref.watch(enableFiltersState));
  return data;
});

// Provider for Book Info Details
final bookInfoProvider =
    FutureProvider.family<BookInfoData, String>((ref, url) async {
  final AnnasArchieve annasArchieve = AnnasArchieve();
  final donationKey = ref.watch(donationKeyProvider);
  BookInfoData data =
      await annasArchieve.bookInfo(url: url, donationKey: donationKey);
  return data;
});

// My Library Database Providers
final myLibraryProvider = FutureProvider((ref) async {
  return dataBase.getAll();
});

final checkIdExists =
    FutureProvider.family.autoDispose<bool, String>((ref, id) async {
  return await dataBase.checkIdExists(id);
});

final getBookByIdProvider =
    FutureProvider.family.autoDispose<MyBook?, String>((ref, id) async {
  return await dataBase.getId(id);
});

final deleteFileFromMyLib =
    FutureProvider.family<void, FileName>((ref, fileName) async {
  return await deleteFileWithDbData(ref, fileName.md5, fileName.format,
      fileName: fileName.fileName);
});

final filePathProvider =
    FutureProvider.family<String, String>((ref, fileName) async {
  // NOTE: Assuming getFilePath is a function in files.dart
  String path = await getFilePath(fileName);
  return path;
});

final getBookPosition =
    FutureProvider.family.autoDispose<String?, String>((ref, fileName) async {
  return await dataBase.getBookState(fileName);
});

// ====================================================================
// BOOK STATE PERSISTENCE FUNCTIONS
// ====================================================================

Future<void> savePdfState(String fileName, WidgetRef ref) async {
  String position = ref.watch(pdfCurrentPage).toString();
  await dataBase.saveBookState(fileName, position);
}

Future<void> saveEpubState(
    String fileName, String? position, WidgetRef ref) async {
  String pos = position ?? '';
  await dataBase.saveBookState(fileName, pos);
}
