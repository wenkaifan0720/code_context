import 'package:sqlite3/sqlite3.dart';

/// SQLite-backed code index for querying SCIP data via SQL.
///
/// Provides a clean SQL interface to symbol, occurrence, and relationship data
/// loaded from SCIP protobuf files. The database is created in-memory by default.
///
/// ## Schema
///
/// Three main tables:
/// - `symbols`: Symbol definitions (classes, methods, functions, etc.)
/// - `occurrences`: Where symbols are defined and referenced
/// - `relationships`: Type hierarchy and call graph edges
///
/// ## Usage
///
/// ```dart
/// final db = SqlIndex.inMemory();
/// // ... populate with ScipToSql converter ...
///
/// final results = db.select('SELECT * FROM symbols WHERE name LIKE ?', ['%Service%']);
/// for (final row in results) {
///   print('${row['name']} (${row['kind']})');
/// }
///
/// db.dispose();
/// ```
class SqlIndex {
  SqlIndex._(this._db);

  /// Create an in-memory SQLite database.
  factory SqlIndex.inMemory() {
    final db = sqlite3.openInMemory();
    final index = SqlIndex._(db);
    index._createSchema();
    return index;
  }

  /// Create a persistent SQLite database at the given path.
  factory SqlIndex.persistent(String path) {
    final db = sqlite3.open(path);
    final index = SqlIndex._(db);
    index._createSchema();
    return index;
  }

  final Database _db;

  /// Create the database schema.
  void _createSchema() {
    _db.execute('''
      -- Symbol definitions
      CREATE TABLE IF NOT EXISTS symbols (
        scip_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        file TEXT,
        line INTEGER,
        column_num INTEGER,
        package TEXT,
        version TEXT,
        container_id TEXT,
        display_name TEXT,
        documentation TEXT,
        language TEXT
      );

      -- Symbol occurrences (definitions and references)
      CREATE TABLE IF NOT EXISTS occurrences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        symbol_id TEXT NOT NULL,
        file TEXT NOT NULL,
        line INTEGER NOT NULL,
        column_num INTEGER NOT NULL,
        end_line INTEGER,
        end_column INTEGER,
        is_definition INTEGER NOT NULL DEFAULT 0,
        enclosing_end_line INTEGER,
        FOREIGN KEY (symbol_id) REFERENCES symbols(scip_id)
      );

      -- Symbol relationships (hierarchy, calls, etc.)
      CREATE TABLE IF NOT EXISTS relationships (
        from_symbol TEXT NOT NULL,
        to_symbol TEXT NOT NULL,
        kind TEXT NOT NULL,
        PRIMARY KEY (from_symbol, to_symbol, kind)
      );

      -- Indexes for fast lookups
      CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
      CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind);
      CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file);
      CREATE INDEX IF NOT EXISTS idx_symbols_package ON symbols(package);
      CREATE INDEX IF NOT EXISTS idx_symbols_container ON symbols(container_id);
      CREATE INDEX IF NOT EXISTS idx_occurrences_symbol ON occurrences(symbol_id);
      CREATE INDEX IF NOT EXISTS idx_occurrences_file ON occurrences(file);
      CREATE INDEX IF NOT EXISTS idx_occurrences_def ON occurrences(is_definition);
      CREATE INDEX IF NOT EXISTS idx_relationships_from ON relationships(from_symbol);
      CREATE INDEX IF NOT EXISTS idx_relationships_to ON relationships(to_symbol);
      CREATE INDEX IF NOT EXISTS idx_relationships_kind ON relationships(kind);
    ''');
  }

  /// Execute a read-only SQL query and return results.
  ///
  /// Throws [SqlExecutionError] if the query attempts to modify data.
  List<Map<String, Object?>> select(String sql, [List<Object?> parameters = const []]) {
    // Basic read-only check
    final normalized = sql.trim().toUpperCase();
    if (!normalized.startsWith('SELECT') && 
        !normalized.startsWith('WITH') &&
        !normalized.startsWith('EXPLAIN')) {
      throw SqlExecutionError('Only SELECT queries are allowed. Got: ${sql.substring(0, sql.length.clamp(0, 50))}...');
    }

    try {
      final stmt = _db.prepare(sql);
      try {
        final result = stmt.select(parameters);
        final columnNames = result.columnNames;
        return result.map((row) => _rowToMap(row, columnNames)).toList();
      } finally {
        stmt.dispose();
      }
    } on SqliteException catch (e) {
      throw SqlExecutionError('SQL error: ${e.message}', sql: sql, cause: e);
    }
  }

  /// Execute a write operation (INSERT, UPDATE, DELETE).
  ///
  /// This is used internally by the SCIP-to-SQL converter.
  /// External callers should use [select] for read-only queries.
  void execute(String sql, [List<Object?> parameters = const []]) {
    try {
      final stmt = _db.prepare(sql);
      try {
        stmt.execute(parameters);
      } finally {
        stmt.dispose();
      }
    } on SqliteException catch (e) {
      throw SqlExecutionError('SQL error: ${e.message}', sql: sql, cause: e);
    }
  }

  /// Execute multiple statements in a single call.
  void executeMultiple(String sql) {
    try {
      _db.execute(sql);
    } on SqliteException catch (e) {
      throw SqlExecutionError('SQL error: ${e.message}', sql: sql, cause: e);
    }
  }

  /// Get column names for a query result.
  List<String> getColumns(String sql, [List<Object?> parameters = const []]) {
    final stmt = _db.prepare(sql);
    try {
      final result = stmt.select(parameters);
      return result.columnNames.toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Begin a transaction for batch operations.
  void beginTransaction() {
    _db.execute('BEGIN TRANSACTION');
  }

  /// Commit the current transaction.
  void commit() {
    _db.execute('COMMIT');
  }

  /// Rollback the current transaction.
  void rollback() {
    _db.execute('ROLLBACK');
  }

  /// Get database statistics.
  Map<String, int> get stats {
    final symbolCount = _db.select('SELECT COUNT(*) as c FROM symbols').first['c'] as int;
    final occurrenceCount = _db.select('SELECT COUNT(*) as c FROM occurrences').first['c'] as int;
    final relationshipCount = _db.select('SELECT COUNT(*) as c FROM relationships').first['c'] as int;
    
    return {
      'symbols': symbolCount,
      'occurrences': occurrenceCount,
      'relationships': relationshipCount,
    };
  }

  /// Get the schema as a string (for documentation).
  String get schema {
    final tables = _db.select(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    );
    return tables.map((t) => t['sql'] as String).join('\n\n');
  }

  /// Convert a Row to a Map with column names as keys.
  Map<String, Object?> _rowToMap(Row row, List<String> columnNames) {
    final map = <String, Object?>{};
    for (var i = 0; i < columnNames.length; i++) {
      map[columnNames[i]] = row.columnAt(i);
    }
    return map;
  }

  /// Dispose of the database connection.
  void dispose() {
    _db.dispose();
  }
}

/// Error thrown when SQL execution fails.
class SqlExecutionError implements Exception {
  SqlExecutionError(this.message, {this.sql, this.cause});

  final String message;
  final String? sql;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('SqlExecutionError: $message');
    if (sql != null) {
      buffer.writeln();
      buffer.write('SQL: $sql');
    }
    return buffer.toString();
  }
}
