import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('SqlIndex', () {
    late SqlIndex index;

    setUp(() async {
      index = SqlIndex.inMemory();
    });

    tearDown(() {
      index.dispose();
    });

    group('schema', () {
      test('creates all required tables', () {
        final tables =
            index.select("SELECT name FROM sqlite_master WHERE type='table'");
        final tableNames = tables.map((r) => r['name'] as String).toSet();

        expect(tableNames, contains('symbols'));
        expect(tableNames, contains('occurrences'));
        expect(tableNames, contains('relationships'));
      });

      test('creates indexes for efficient queries', () {
        final indexes = index.select(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
        );

        expect(indexes.length, greaterThan(0));
      });
    });

    group('symbol operations', () {
      test('insert and query symbols', () {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'MyClass', 'class', 'lib/main.dart']);

        final result = index.select(
          'SELECT name, kind FROM symbols WHERE scip_id = ?',
          ['test . . . lib/main.dart/MyClass#'],
        );
        expect(result, hasLength(1));
        expect(result.first['name'], equals('MyClass'));
        expect(result.first['kind'], equals('class'));
      });

      test('supports container relationships', () {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'MyClass', 'class', 'lib/main.dart']);

        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file, container_id)
          VALUES (?, ?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#doWork().', 'doWork', 'method', 'lib/main.dart', 'test . . . lib/main.dart/MyClass#']);

        final result = index.select(
          'SELECT name, container_id FROM symbols WHERE name = ?',
          ['doWork'],
        );
        expect(result.first['container_id'], equals('test . . . lib/main.dart/MyClass#'));
      });
    });

    group('occurrence operations', () {
      setUp(() {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'MyClass', 'class', 'lib/main.dart']);
      });

      test('insert definition occurrence', () {
        index.execute('''
          INSERT INTO occurrences (symbol_id, file, line, column_num, is_definition)
          VALUES (?, ?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'lib/main.dart', 10, 6, 1]);

        final result = index.select(
          'SELECT * FROM occurrences WHERE symbol_id = ? AND is_definition = 1',
          ['test . . . lib/main.dart/MyClass#'],
        );
        expect(result, hasLength(1));
        expect(result.first['line'], equals(10));
      });

      test('insert reference occurrence', () {
        index.execute('''
          INSERT INTO occurrences (symbol_id, file, line, column_num, is_definition)
          VALUES (?, ?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'lib/other.dart', 20, 0, 0]);

        final result = index.select(
          'SELECT * FROM occurrences WHERE symbol_id = ? AND is_definition = 0',
          ['test . . . lib/main.dart/MyClass#'],
        );
        expect(result, hasLength(1));
      });
    });

    group('relationship operations', () {
      setUp(() {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'MyClass', 'class', 'lib/main.dart']);
        
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/main.dart/MyInterface#', 'MyInterface', 'interface', 'lib/main.dart']);
      });

      test('insert relationship', () {
        index.execute('''
          INSERT INTO relationships (from_symbol, to_symbol, kind)
          VALUES (?, ?, ?)
        ''', ['test . . . lib/main.dart/MyClass#', 'test . . . lib/main.dart/MyInterface#', 'implements']);

        final result = index.select(
          'SELECT * FROM relationships WHERE from_symbol = ?',
          ['test . . . lib/main.dart/MyClass#'],
        );
        expect(result, hasLength(1));
        expect(result.first['kind'], equals('implements'));
      });
    });

    group('query operations', () {
      setUp(() {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/auth.dart/AuthService#', 'AuthService', 'class', 'lib/auth.dart']);
        
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/auth.dart/AuthRepo#', 'AuthRepo', 'class', 'lib/auth.dart']);
        
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/auth.dart/login#', 'login', 'function', 'lib/auth.dart']);
      });

      test('query with GLOB pattern works', () {
        final result = index.select(
          "SELECT name FROM symbols WHERE name GLOB 'Auth*'",
        );
        expect(result.length, equals(2));
      });

      test('query with LIKE pattern works', () {
        final result = index.select(
          "SELECT name FROM symbols WHERE name LIKE '%Service'",
        );
        expect(result.length, equals(1));
        expect(result.first['name'], equals('AuthService'));
      });
    });

    group('stats', () {
      test('returns correct counts', () {
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/test.dart/A#', 'A', 'class', 'lib/test.dart']);
        
        index.execute('''
          INSERT INTO symbols (scip_id, name, kind, file)
          VALUES (?, ?, ?, ?)
        ''', ['test . . . lib/test.dart/B#', 'B', 'class', 'lib/test.dart']);

        final stats = index.stats;
        expect(stats['symbols'], equals(2));
      });
    });

    group('read-only enforcement', () {
      test('select rejects non-SELECT queries', () {
        expect(
          () => index.select("INSERT INTO symbols VALUES ('a', 'b', 'c', 'd')"),
          throwsA(isA<SqlExecutionError>()),
        );
      });
    });
  });
}
