import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('SqlExecutor', () {
    late SqlIndex index;
    late SqlExecutor executor;

    setUp(() async {
      index = SqlIndex.inMemory();
      executor = SqlExecutor(index);

      // Populate with test data
      index.execute('''
        INSERT INTO symbols (scip_id, name, kind, file, documentation)
        VALUES (?, ?, ?, ?, ?)
      ''', ['test . . . lib/main.dart/UserService#', 'UserService', 'class', 'lib/main.dart', 'A service for managing users.']);

      index.execute('''
        INSERT INTO symbols (scip_id, name, kind, file, container_id)
        VALUES (?, ?, ?, ?, ?)
      ''', ['test . . . lib/main.dart/UserService#getUser().', 'getUser', 'method', 'lib/main.dart', 'test . . . lib/main.dart/UserService#']);

      index.execute('''
        INSERT INTO symbols (scip_id, name, kind, file)
        VALUES (?, ?, ?, ?)
      ''', ['test . . . lib/main.dart/login#', 'login', 'function', 'lib/main.dart']);
    });

    tearDown(() {
      index.dispose();
    });

    group('execute', () {
      test('executes valid SELECT query', () {
        final result = executor.execute('SELECT name FROM symbols');

        expect(result.columns, contains('name'));
        expect(result.rows.length, equals(3));
      });

      test('returns proper column names', () {
        final result = executor.execute(
          'SELECT name, kind FROM symbols WHERE kind = "class"',
        );

        expect(result.columns, equals(['name', 'kind']));
        expect(result.rows.length, equals(1));
        expect(result.rows.first['name'], equals('UserService'));
      });

      test('supports aggregate functions', () {
        final result = executor.execute(
          'SELECT COUNT(*) as count FROM symbols',
        );

        expect(result.rows.first['count'], equals(3));
      });

      test('supports subqueries via container_id', () {
        final result = executor.execute('''
          SELECT name FROM symbols 
          WHERE container_id = 'test . . . lib/main.dart/UserService#'
        ''');

        expect(result.rows.length, equals(1));
        expect(result.rows.first['name'], equals('getUser'));
      });
    });

    group('read-only enforcement', () {
      test('rejects INSERT via executor', () {
        // SqlExecutor.execute calls SqlIndex.select which only allows SELECT
        expect(
          () => executor.execute("INSERT INTO symbols VALUES (1, 'x', 'x', 'x')"),
          throwsA(isA<SqlExecutionError>()),
        );
      });

      test('rejects UPDATE via executor', () {
        expect(
          () => executor.execute("UPDATE symbols SET name = 'x'"),
          throwsA(isA<SqlExecutionError>()),
        );
      });

      test('rejects DELETE via executor', () {
        expect(
          () => executor.execute("DELETE FROM symbols"),
          throwsA(isA<SqlExecutionError>()),
        );
      });
    });

    group('error handling', () {
      test('throws for invalid SQL syntax', () {
        expect(
          () => executor.execute('SELEKT * FROM symbols'),
          throwsA(isA<SqlExecutionError>()),
        );
      });

      test('throws for unknown table', () {
        expect(
          () => executor.execute('SELECT * FROM nonexistent'),
          throwsA(isA<SqlExecutionError>()),
        );
      });

      test('throws for unknown column', () {
        expect(
          () => executor.execute('SELECT nonexistent FROM symbols'),
          throwsA(isA<SqlExecutionError>()),
        );
      });
    });

    group('SqlResult', () {
      test('toText returns markdown table', () {
        final result = executor.execute(
          'SELECT name, kind FROM symbols ORDER BY name LIMIT 2',
        );

        final text = result.toText();

        expect(text, contains('| name'));
        expect(text, contains('|---'));
      });

      test('toText returns "(0 rows)" for empty', () {
        final result = executor.execute(
          "SELECT * FROM symbols WHERE name = 'nonexistent'",
        );

        expect(result.toText(), contains('(0 rows)'));
      });

      test('toJson returns structured data', () {
        final result = executor.execute(
          'SELECT name FROM symbols LIMIT 1',
        );

        final json = result.toJson();

        expect(json, contains('columns'));
        expect(json, contains('rows'));
      });
    });
  });
}
