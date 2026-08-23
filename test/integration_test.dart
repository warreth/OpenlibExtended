import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/ddos_protection_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_ffi for desktop test environments
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  group('Integration Tests - Real Network Calls', () {
    late AnnasArchieve api;
    late InstanceManager instanceManager;

    setUp(() {
      api = AnnasArchieve();
      instanceManager = InstanceManager();
    });

    test('Search for a well-known public domain book returns results', () async {
      // Search for "Pride and Prejudice" - public domain, widely mirrored
      final results = await api.searchBooks(
        searchQuery: 'Pride and Prejudice',
        fileType: 'epub',
        enableFilters: true,
      );

      expect(results, isNotEmpty, reason: 'Search should return at least one result');
      expect(results.first.title.toLowerCase(), contains('pride'));
      expect(results.first.md5, isNotEmpty);
      expect(results.first.link, startsWith('http'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get book details for a known book returns mirror links', () async {
      // First search for the book
      final results = await api.searchBooks(
        searchQuery: 'The Great Gatsby',
        fileType: 'epub',
        enableFilters: true,
      );

      expect(results, isNotEmpty);
      final firstBook = results.first;

      // Then fetch book details
      final bookInfo = await api.bookInfo(url: firstBook.link);

      expect(bookInfo, isNotNull);
      expect(bookInfo.title, isNotEmpty);
      expect(bookInfo.md5, equals(firstBook.md5));
      expect(bookInfo.format, isNotEmpty);
      // Mirror can be null if DDoS protected, but should be extracted if available
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('InstanceManager returns active mirrors', () async {
      final instances = await instanceManager.getInstances();
      
      expect(instances, isNotEmpty, reason: 'Should have at least default mirrors');
      
      final enabledInstances = instances.where((i) => i.enabled).toList();
      expect(enabledInstances, isNotEmpty, reason: 'Should have at least one enabled mirror');
      
      // Check default mirrors are present
      final hasGl = instances.any((i) => i.baseUrl.contains('annas-archive.gl'));
      final hasPk = instances.any((i) => i.baseUrl.contains('annas-archive.pk'));
      final hasGd = instances.any((i) => i.baseUrl.contains('annas-archive.gd'));
      
      expect(hasGl || hasPk || hasGd, isTrue, 
        reason: 'Should have at least one of the official mirrors');
    });

    test('DDoS handler stores and retrieves cookies correctly', () async {
      final handler = DDoSProtectionHandler();
      final testDomain = 'annas-archive.pk';
      
      // Clear any existing cookies first
      await handler.clearCookies(testDomain);
      
      // Store test cookies
      final testCookies = [
        Cookie('cf_clearance', 'test_token_123'),
        Cookie('session_id', 'sess_abc'),
      ];
      
      await handler.storeCookies(testDomain, testCookies);
      
      // Retrieve and verify
      final retrieved = await handler.getCookies(testDomain);
      
      expect(retrieved, isNotNull);
      expect(retrieved!.length, equals(2));
      expect(retrieved.any((c) => c.name == 'cf_clearance' && c.value == 'test_token_123'), isTrue);
      expect(retrieved.any((c) => c.name == 'session_id' && c.value == 'sess_abc'), isTrue);
      
      // Clean up
      await handler.clearCookies(testDomain);
    });

    test('Search with filters applies correct query parameters', () async {
      // This tests the full flow: URL encoding -> request -> parsing
      final results = await api.searchBooks(
        searchQuery: 'Sherlock Holmes',
        content: 'book_fiction',
        sort: 'newest',
        fileType: 'epub',
        language: 'en',
        enableFilters: true,
      );

      // Should return results for English fiction EPUBs
      expect(results, isNotEmpty);
      
      // Verify format filtering worked
      for (final book in results.take(3)) {
        expect(book.info?.toLowerCase(), contains('epub'));
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }, 
  skip: 'Integration tests require network access and may be blocked by DDoS protection');
}
