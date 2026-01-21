import 'dart:io';

import 'package:scip_server/scip_server.dart';

/// Language-agnostic semantic code intelligence with SQL query interface.
///
/// Provides incremental indexing and SQL queries for navigating
/// codebases in any supported language.
///
/// ## Usage
///
/// ```dart
/// // Auto-detect language from project files
/// final context = await CodeContext.open('/path/to/project');
///
/// // Query with SQL
/// final result = await context.sql('SELECT * FROM symbols WHERE name = ?', ['MyClass']);
/// print(result.toText());
///
/// // Load dependencies for cross-package queries
/// await context.loadDependencies();
///
/// // Query across packages
/// final result = await context.sql('''
///   SELECT name, kind, package FROM symbols
///   WHERE name LIKE '%Widget%' AND kind = 'class'
/// ''');
///
/// // Cleanup
/// await context.dispose();
/// ```
///
/// ## SQL Schema
///
/// Three main tables are available:
///
/// ### symbols
/// - `scip_id` (TEXT PRIMARY KEY) - SCIP symbol identifier
/// - `name` (TEXT) - Symbol name
/// - `kind` (TEXT) - Symbol kind (class, method, function, field, etc.)
/// - `file` (TEXT) - Relative file path (NULL for external symbols)
/// - `line` (INTEGER) - Definition line number (0-indexed)
/// - `column_num` (INTEGER) - Definition column number
/// - `package` (TEXT) - Package name
/// - `version` (TEXT) - Package version
/// - `container_id` (TEXT) - Parent symbol SCIP ID
/// - `display_name` (TEXT) - Human-readable display name
/// - `documentation` (TEXT) - Documentation string
/// - `language` (TEXT) - Language identifier
///
/// ### occurrences
/// - `id` (INTEGER PRIMARY KEY) - Auto-increment ID
/// - `symbol_id` (TEXT) - References symbols.scip_id
/// - `file` (TEXT) - File path
/// - `line` (INTEGER) - Line number (0-indexed)
/// - `column_num` (INTEGER) - Column number
/// - `end_line` (INTEGER) - End line number
/// - `end_column` (INTEGER) - End column number
/// - `is_definition` (INTEGER) - 1 if definition, 0 if reference
/// - `enclosing_end_line` (INTEGER) - End line of enclosing scope
///
/// ### relationships
/// - `from_symbol` (TEXT) - Source symbol SCIP ID
/// - `to_symbol` (TEXT) - Target symbol SCIP ID
/// - `kind` (TEXT) - Relationship kind (implements, calls, type_definition, references)
///
/// ## Supported Languages
///
/// - Dart (via `DartBinding` from `dart_binding` package)
/// - More languages coming soon...
class CodeContext {
  CodeContext._({
    required LanguageContext languageContext,
    required SqlIndex sqlIndex,
    required SqlExecutor executor,
  })  : _context = languageContext,
        _sqlIndex = sqlIndex,
        _executor = executor;

  final LanguageContext _context;
  final SqlIndex _sqlIndex;
  final SqlExecutor _executor;

  // Registered language bindings for auto-detection
  static final List<LanguageBinding> _registeredBindings = [];

  /// Register a language binding for auto-detection.
  ///
  /// Call this at startup to enable auto-detection of languages:
  /// ```dart
  /// CodeContext.registerBinding(DartBinding());
  /// CodeContext.registerBinding(TypeScriptBinding());
  /// ```
  static void registerBinding(LanguageBinding binding) {
    if (!_registeredBindings.any((b) => b.languageId == binding.languageId)) {
      _registeredBindings.add(binding);
    }
  }

  /// Get all registered language bindings.
  static List<LanguageBinding> get registeredBindings =>
      List.unmodifiable(_registeredBindings);

  /// Open a project with optional language binding.
  ///
  /// If no [binding] is provided, attempts to auto-detect the language
  /// by looking for package manifest files (pubspec.yaml, package.json, etc.)
  /// in registered bindings.
  ///
  /// This will:
  /// 1. Detect or use the specified language binding
  /// 2. Discover all packages in the path
  /// 3. Create indexers for each package
  /// 4. Load from cache (if valid and [useCache] is true)
  /// 5. Build in-memory SQLite database from SCIP data
  /// 6. Start file watching (if [watch] is true)
  ///
  /// Example:
  /// ```dart
  /// // Auto-detect language
  /// final context = await CodeContext.open('/path/to/project');
  ///
  /// // Explicitly specify language
  /// final context = await CodeContext.open(
  ///   '/path/to/project',
  ///   binding: DartBinding(),
  /// );
  /// ```
  static Future<CodeContext> open(
    String projectPath, {
    LanguageBinding? binding,
    bool watch = true,
    bool useCache = true,
    bool loadDependencies = false,
    void Function(String message)? onProgress,
  }) async {
    final normalizedPath = Directory(projectPath).absolute.path;

    // 1. Detect or use specified binding
    final detectedBinding = binding ?? await _detectLanguage(normalizedPath);
    if (detectedBinding == null) {
      throw StateError(
        'Could not detect project language. '
        'Register a binding with CodeContext.registerBinding() or specify one explicitly.',
      );
    }

    onProgress?.call('Using ${detectedBinding.languageId} binding...');

    // 2. Create language context
    final languageContext = await detectedBinding.createContext(
      normalizedPath,
      useCache: useCache,
      watch: watch,
      onProgress: onProgress,
    );

    // 3. Load dependencies if requested
    if (loadDependencies && detectedBinding.supportsDependencies) {
      onProgress?.call('Loading dependencies...');
      await languageContext.loadDependencies();
    }

    // 4. Build SQL index from SCIP data
    onProgress?.call('Building SQL index...');
    final sqlIndex = SqlIndex.inMemory();
    final converter = ScipToSql(sqlIndex);

    // Load project index into SQL
    _loadScipIndexToSql(converter, languageContext.index);

    // Load dependency indexes if available
    for (final depIndex in languageContext.allExternalIndexes) {
      _loadScipIndexToSql(converter, depIndex);
    }

    // 5. Create SQL executor
    final executor = SqlExecutor(sqlIndex);

    onProgress?.call('Ready');

    return CodeContext._(
      languageContext: languageContext,
      sqlIndex: sqlIndex,
      executor: executor,
    );
  }

  /// Load SCIP index data into SQL database.
  static void _loadScipIndexToSql(ScipToSql converter, ScipIndex scipIndex) {
    converter.loadFromScipIndex(scipIndex);
  }

  /// Auto-detect language from project files.
  static Future<LanguageBinding?> _detectLanguage(String path) async {
    for (final binding in _registeredBindings) {
      final packageFile = File('$path/${binding.packageFile}');
      if (await packageFile.exists()) {
        return binding;
      }

      // Also check subdirectories for monorepos
      final dir = Directory(path);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith(binding.packageFile)) {
          return binding;
        }
      }
    }
    return null;
  }

  /// The language binding used for this context.
  LanguageBinding get binding {
    // Get from registered bindings based on context
    return _registeredBindings.firstWhere(
      (b) => b.languageId == languageId,
      orElse: () => throw StateError('No binding found for $languageId'),
    );
  }

  /// The language identifier (e.g., "dart", "typescript").
  String get languageId {
    // Infer from provider or default to first registered
    if (_registeredBindings.isNotEmpty) {
      return _registeredBindings.first.languageId;
    }
    return 'unknown';
  }

  /// The root path for this context.
  String get rootPath => _context.rootPath;

  /// The underlying language context.
  LanguageContext get context => _context;

  /// The SQL database (for advanced use).
  SqlIndex get sqlIndex => _sqlIndex;

  /// All discovered packages.
  List<DiscoveredPackage> get packages => _context.packages;

  /// Number of packages.
  int get packageCount => _context.packageCount;

  /// Stream of index updates from all packages.
  Stream<IndexUpdate> get updates => _context.updates;

  /// Execute a SQL query against the code index.
  ///
  /// Returns a [SqlResult] with rows, columns, and formatting methods.
  ///
  /// ## Example Queries
  ///
  /// ```dart
  /// // Find all classes
  /// final result = await context.sql('SELECT * FROM symbols WHERE kind = ?', ['class']);
  ///
  /// // Find symbol definition
  /// final result = await context.sql('''
  ///   SELECT s.name, s.kind, o.file, o.line
  ///   FROM symbols s
  ///   JOIN occurrences o ON s.scip_id = o.symbol_id
  ///   WHERE s.name = ? AND o.is_definition = 1
  /// ''', ['MyClass']);
  ///
  /// // Find all references
  /// final result = await context.sql('''
  ///   SELECT o.file, o.line, o.column_num
  ///   FROM occurrences o
  ///   JOIN symbols s ON o.symbol_id = s.scip_id
  ///   WHERE s.name = ? AND o.is_definition = 0
  /// ''', ['login']);
  ///
  /// // Get class members
  /// final result = await context.sql('''
  ///   SELECT * FROM symbols
  ///   WHERE container_id = (SELECT scip_id FROM symbols WHERE name = ?)
  /// ''', ['MyClass']);
  ///
  /// // Find callers
  /// final result = await context.sql('''
  ///   SELECT s.name, s.kind, s.file
  ///   FROM relationships r
  ///   JOIN symbols s ON r.from_symbol = s.scip_id
  ///   WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = ?)
  ///     AND r.kind = 'calls'
  /// ''', ['login']);
  /// ```
  SqlResult sql(String query, [List<Object?> parameters = const []]) {
    return _executor.execute(query, parameters);
  }

  /// Get the SQL schema (for documentation).
  String get schema => _sqlIndex.schema;

  /// Manually refresh a specific file.
  ///
  /// Note: After refresh, you should call [rebuildSqlIndex] to update the SQL database.
  Future<bool> refreshFile(String filePath) {
    return _context.refreshFile(filePath);
  }

  /// Manually refresh all files in all packages.
  ///
  /// Note: After refresh, you should call [rebuildSqlIndex] to update the SQL database.
  Future<void> refreshAll() {
    return _context.refreshAll();
  }

  /// Rebuild the SQL index from current SCIP data.
  ///
  /// Call this after [refreshFile] or [refreshAll] to update the SQL database.
  void rebuildSqlIndex() {
    // Clear existing data
    _sqlIndex.execute('DELETE FROM relationships');
    _sqlIndex.execute('DELETE FROM occurrences');
    _sqlIndex.execute('DELETE FROM symbols');

    // Reload
    final converter = ScipToSql(_sqlIndex);
    _loadScipIndexToSql(converter, _context.index);

    for (final depIndex in _context.allExternalIndexes) {
      _loadScipIndexToSql(converter, depIndex);
    }
  }

  /// Get combined index statistics.
  Map<String, dynamic> get stats {
    final sqlStats = _sqlIndex.stats;
    return {
      'files': _context.stats['files'],
      'symbols': sqlStats['symbols'],
      'occurrences': sqlStats['occurrences'],
      'relationships': sqlStats['relationships'],
      'packages': _context.packageCount,
    };
  }

  /// Whether external dependencies are loaded.
  bool get hasDependencies => _context.hasDependencies;

  /// Load external dependencies for cross-package queries.
  ///
  /// For Dart: loads SDK, Flutter, and pub.dev package indexes.
  /// After loading, call [rebuildSqlIndex] to include them in SQL queries.
  Future<void> loadDependencies() async {
    await _context.loadDependencies();
    rebuildSqlIndex();
  }

  /// Dispose of resources.
  ///
  /// Stops file watching, cleans up all indexers, and closes the SQL database.
  Future<void> dispose() async {
    _sqlIndex.dispose();
    await _context.dispose();
  }
}
