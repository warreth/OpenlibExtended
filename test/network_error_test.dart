import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:openlib/services/network_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkError Tests', () {
    test('Identifies HTTP 403 as cloudflareBlock and attaches request URL', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk/search?q=Flutter'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://annas-archive.pk/search?q=Flutter'),
          statusCode: 403,
          data: 'Forbidden',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.cloudflareBlock));
      expect(networkError.blockedUrl, equals('https://annas-archive.pk/search?q=Flutter'));
      expect(networkError.userMessage, contains('DDoS'));
    });

    test('Identifies HTTP 451 as forbidden / regional block', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://welib.org/search'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://welib.org/search'),
          statusCode: 451,
          data: 'Unavailable For Legal Reasons',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.forbidden));
      expect(networkError.userMessage, contains('region'));
    });

    test('Identifies timeout errors correctly', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://annas-archive.gd/search'),
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timeout',
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.timeout));
    });
  });
}
