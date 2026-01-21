import 'dart:convert';

import 'sql_index.dart';

/// Executes SQL queries and formats results.
///
/// Provides a high-level interface for running read-only SQL queries
/// against the code index, with support for JSON and text output formats.
///
/// ## Usage
///
/// ```dart
/// final executor = SqlExecutor(sqlIndex);
///
/// // Execute and get formatted result
/// final result = executor.execute('SELECT * FROM symbols WHERE name = ?', ['MyClass']);
/// print(result.toText()); // Markdown table
/// print(result.toJson()); // JSON array
/// ```
class SqlExecutor {
  SqlExecutor(this._db);

  final SqlIndex _db;

  /// Maximum number of rows to return (prevents runaway queries).
  static const int maxRows = 10000;

  /// Execute a SQL query and return a formatted result.
  SqlResult execute(String sql, [List<Object?> parameters = const []]) {
    final stopwatch = Stopwatch()..start();

    try {
      // Get column names first
      final columns = _db.getColumns(sql, parameters);

      // Execute query
      final rows = _db.select(sql, parameters);

      stopwatch.stop();

      // Enforce row limit
      final truncated = rows.length > maxRows;
      final limitedRows = truncated ? rows.take(maxRows).toList() : rows;

      return SqlResult(
        columns: columns,
        rows: limitedRows,
        totalRows: rows.length,
        truncated: truncated,
        queryTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on SqlExecutionError {
      rethrow;
    } catch (e) {
      throw SqlExecutionError('Query execution failed: $e', sql: sql, cause: e);
    }
  }

  /// Get the database schema description.
  String getSchema() {
    return _db.schema;
  }

  /// Get database statistics.
  Map<String, int> getStats() {
    return _db.stats;
  }
}

/// Result of a SQL query.
class SqlResult {
  SqlResult({
    required this.columns,
    required this.rows,
    required this.totalRows,
    required this.truncated,
    required this.queryTimeMs,
  });

  /// Column names in the result set.
  final List<String> columns;

  /// Result rows as maps of column name to value.
  final List<Map<String, Object?>> rows;

  /// Total number of rows before truncation.
  final int totalRows;

  /// Whether the result was truncated due to row limit.
  final bool truncated;

  /// Query execution time in milliseconds.
  final int queryTimeMs;

  /// Whether the query returned no results.
  bool get isEmpty => rows.isEmpty;

  /// Number of rows in the result.
  int get rowCount => rows.length;

  /// Convert to a Map for JSON serialization.
  Map<String, dynamic> toMap() {
    return {
      'columns': columns,
      'rows': rows,
      'rowCount': totalRows,
      'truncated': truncated,
      'queryTimeMs': queryTimeMs,
    };
  }

  /// Convert to JSON string.
  String toJson({bool pretty = false}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toMap());
    }
    return jsonEncode(toMap());
  }

  /// Convert to a Markdown table.
  String toText() {
    if (rows.isEmpty) {
      return '(0 rows)';
    }

    final buffer = StringBuffer();

    // Calculate column widths
    final widths = <String, int>{};
    for (final col in columns) {
      widths[col] = col.length;
    }
    for (final row in rows) {
      for (final col in columns) {
        final value = _formatValue(row[col]);
        if (value.length > widths[col]!) {
          widths[col] = value.length;
        }
      }
    }

    // Check if table would be too wide (>120 chars)
    final totalWidth =
        widths.values.fold(0, (a, b) => a + b) + (columns.length * 3) + 1;

    if (totalWidth > 120 && rows.length <= 20) {
      // Use vertical format for wide tables
      return _toVerticalFormat();
    }

    // Header row
    buffer.write('| ');
    for (var i = 0; i < columns.length; i++) {
      if (i > 0) buffer.write(' | ');
      buffer.write(columns[i].padRight(widths[columns[i]]!));
    }
    buffer.writeln(' |');

    // Separator row
    buffer.write('|');
    for (final col in columns) {
      buffer.write('-' * (widths[col]! + 2));
      buffer.write('|');
    }
    buffer.writeln();

    // Data rows
    for (final row in rows) {
      buffer.write('| ');
      for (var i = 0; i < columns.length; i++) {
        if (i > 0) buffer.write(' | ');
        final value = _formatValue(row[columns[i]]);
        buffer.write(value.padRight(widths[columns[i]]!));
      }
      buffer.writeln(' |');
    }

    // Footer
    buffer.writeln();
    if (truncated) {
      buffer.writeln('($totalRows rows, showing first $rowCount)');
    } else {
      buffer.writeln('($rowCount rows)');
    }

    return buffer.toString();
  }

  /// Format result in vertical mode (one row per block).
  String _toVerticalFormat() {
    final buffer = StringBuffer();

    for (var i = 0; i < rows.length; i++) {
      buffer.writeln('-[ Row ${i + 1} ]${'─' * 40}');
      final row = rows[i];
      for (final col in columns) {
        buffer.writeln('$col: ${_formatValue(row[col])}');
      }
      if (i < rows.length - 1) buffer.writeln();
    }

    buffer.writeln();
    if (truncated) {
      buffer.writeln('($totalRows rows, showing first $rowCount)');
    } else {
      buffer.writeln('($rowCount rows)');
    }

    return buffer.toString();
  }

  /// Format a single value for display.
  String _formatValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is String) {
      // Truncate long strings
      if (value.length > 100) {
        return '${value.substring(0, 97)}...';
      }
      return value;
    }
    return value.toString();
  }
}
