import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:test/test.dart';

void main() {
  group('CodeContext SQL Integration', () {
    late Directory tempDir;
    late CodeContext context;

    setUp(() async {
      // Register the Dart binding
      CodeContext.registerBinding(DartBinding());

      // Create a temp project with pubspec.yaml
      tempDir = await Directory.systemTemp.createTemp('code_context_sql_test_');

      // Create pubspec.yaml
      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_project
environment:
  sdk: ^3.0.0
''');

      // Create .dart_tool/package_config.json
      await Directory('${tempDir.path}/.dart_tool').create();
      await File('${tempDir.path}/.dart_tool/package_config.json')
          .writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "test_project",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ]
}
''');

      // Create lib/ with test dart files
      await Directory('${tempDir.path}/lib').create();
      await File('${tempDir.path}/lib/main.dart').writeAsString('''
/// Main entry point.
void main() {
  final service = AuthService();
  service.login('user', 'pass');
}

/// Authentication service.
class AuthService {
  /// Authenticates a user.
  void login(String username, String password) {
    print('Logging in \$username');
  }
  
  /// Logs out the current user.
  void logout() {
    print('Logged out');
  }
}

/// User repository.
class UserRepository {
  List<String> getUsers() => [];
}
''');

      await File('${tempDir.path}/lib/utils.dart').writeAsString('''
/// Utility functions.

/// Validates an email address.
bool isValidEmail(String email) {
  return email.contains('@');
}

/// Formats a date.
String formatDate(DateTime date) {
  return date.toIso8601String();
}
''');

      // Open context (this indexes and creates SQL database)
      context = await CodeContext.open(
        tempDir.path,
        watch: false,
        useCache: false,
      );
    });

    tearDown(() async {
      await context.dispose();
      await tempDir.delete(recursive: true);
    });

    group('sql queries', () {
      test('queries symbols by name', () {
        final result = context.sql(
          "SELECT name, kind FROM symbols WHERE name = 'AuthService'",
        );

        expect(result.rows.length, equals(1));
        expect(result.rows.first['name'], equals('AuthService'));
        expect(result.rows.first['kind'], equals('class'));
      });

      test('queries symbols with GLOB pattern', () {
        final result = context.sql(
          "SELECT name FROM symbols WHERE name GLOB '*Service*'",
        );

        expect(result.rows.length, equals(1));
        expect(result.rows.first['name'], equals('AuthService'));
      });

      test('queries files via symbols.file', () {
        final result = context.sql('SELECT DISTINCT file FROM symbols');

        final files = result.rows.map((r) => r['file'] as String?).whereType<String>().toList();
        expect(files.any((f) => f.contains('main.dart')), isTrue);
        expect(files.any((f) => f.contains('utils.dart')), isTrue);
      });

      test('queries symbol counts', () {
        final result = context.sql(
          'SELECT COUNT(*) as count FROM symbols',
        );

        expect(result.rows.first['count'], greaterThan(0));
      });

      test('queries members via container relationship', () {
        final result = context.sql('''
          SELECT child.name, child.kind 
          FROM symbols child
          WHERE child.container_id = (
            SELECT scip_id FROM symbols WHERE name = 'AuthService'
          )
        ''');

        final memberNames = result.rows.map((r) => r['name']).toSet();
        expect(memberNames, contains('login'));
        expect(memberNames, contains('logout'));
      });

      test('queries occurrences', () {
        final result = context.sql('''
          SELECT s.name, o.line, o.is_definition
          FROM occurrences o
          JOIN symbols s ON o.symbol_id = s.scip_id
          WHERE s.name = 'AuthService'
        ''');

        expect(result.rows.length, greaterThanOrEqualTo(1));
        // Should have at least one definition
        expect(
          result.rows.any((r) => r['is_definition'] == 1),
          isTrue,
        );
      });

      test('queries symbols by kind', () {
        final result = context.sql(
          "SELECT name FROM symbols WHERE kind = 'function'",
        );

        final names = result.rows.map((r) => r['name']).toSet();
        expect(names, containsAll(['main', 'isValidEmail', 'formatDate']));
      });

      test('rejects write operations', () {
        expect(
          () => context.sql('DELETE FROM symbols'),
          throwsA(isA<SqlExecutionError>()),
        );
      });

      test('returns formatted result as text', () {
        final result = context.sql(
          'SELECT name, kind FROM symbols ORDER BY name LIMIT 3',
        );

        final text = result.toText();

        expect(text, contains('| name'));
        expect(text, contains('| kind'));
      });

      test('returns formatted result as JSON', () {
        final result = context.sql(
          'SELECT name FROM symbols LIMIT 1',
        );

        final json = result.toJson();

        expect(json, contains('columns'));
        expect(json, contains('rows'));
      });
    });

    group('complex queries', () {
      test('aggregates by kind', () {
        final result = context.sql('''
          SELECT kind, COUNT(*) as count 
          FROM symbols 
          GROUP BY kind 
          ORDER BY count DESC
        ''');

        expect(result.rows.length, greaterThan(0));
        expect(result.rows.first.containsKey('count'), isTrue);
      });

      test('finds symbols defined in specific file', () {
        final result = context.sql('''
          SELECT name, kind
          FROM symbols
          WHERE file LIKE '%utils.dart'
        ''');

        final names = result.rows.map((r) => r['name']).toSet();
        expect(names, contains('isValidEmail'));
        expect(names, contains('formatDate'));
      });

      test('finds all occurrences of a symbol', () {
        final result = context.sql('''
          SELECT o.file, o.line, o.is_definition
          FROM occurrences o
          JOIN symbols s ON o.symbol_id = s.scip_id
          WHERE s.name = 'AuthService'
          ORDER BY o.line
        ''');

        expect(result.rows.length, greaterThanOrEqualTo(1));
      });
    });
  });
}
