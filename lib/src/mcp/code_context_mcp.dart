import 'dart:async';
import 'dart:io';

import 'package:dart_binding/dart_binding.dart';
import 'package:dart_mcp/server.dart';

import '../code_context.dart';

/// Mix this in to any MCPServer to add code intelligence via code_context.
///
/// Provides SQL-based code intelligence for Dart codebases.
///
/// ## Available Tools
///
/// - `dart_sql` - Execute SQL queries against the code index
/// - `dart_schema` - Show the SQL schema for reference
/// - `dart_index_flutter` - Index Flutter SDK packages
/// - `dart_index_deps` - Index pub dependencies
/// - `dart_refresh` - Refresh project index
/// - `dart_status` - Show index status
///
/// Example usage:
/// ```dart
/// class MyServer extends MCPServer with CodeContextSupport {
///   // ...
/// }
/// ```
base mixin CodeContextSupport on ToolsSupport, RootsTrackingSupport {
  /// Cached CodeContext instances per project root.
  final Map<String, CodeContext> _contexts = {};

  /// Get the Dart registry from a context (Dart-specific).
  PackageRegistry? _getRegistry(CodeContext context) {
    final langContext = context.context;
    if (langContext is DartLanguageContext) {
      return langContext.registry;
    }
    return null;
  }

  /// File watchers for package_config.json per project root.
  final Map<String, StreamSubscription<FileSystemEvent>>
      _packageConfigWatchers = {};

  /// Roots marked as stale (package_config changed since last refresh).
  final Set<String> _staleRoots = {};

  /// Whether to use cached indexes.
  bool get useCache => true;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) async {
    final result = await super.initialize(request);

    if (!supportsRoots) {
      log(
        LoggingLevel.warning,
        'CodeContextSupport requires the "roots" capability which is not '
        'supported. Query tools have been disabled.',
      );
      return result;
    }

    // Register available language bindings for auto-detection
    CodeContext.registerBinding(DartBinding());

    // Register tools
    registerTool(dartSqlTool, _handleDartSql);
    registerTool(dartSchemaTool, _handleDartSchema);
    registerTool(dartIndexFlutterTool, _handleIndexFlutter);
    registerTool(dartIndexDepsTool, _handleIndexDeps);
    registerTool(dartRefreshTool, _handleRefresh);
    registerTool(dartStatusTool, _handleStatus);

    return result;
  }

  @override
  Future<void> updateRoots() async {
    await super.updateRoots();

    final currentRoots = await roots;
    final currentRootUris = currentRoots.map((r) => r.uri).toSet();

    // Remove contexts and watchers for roots that no longer exist
    final removedRoots =
        _contexts.keys.where((r) => !currentRootUris.contains(r)).toList();
    for (final root in removedRoots) {
      await _contexts[root]?.dispose();
      _contexts.remove(root);
      await _packageConfigWatchers[root]?.cancel();
      _packageConfigWatchers.remove(root);
      _staleRoots.remove(root);
      log(LoggingLevel.debug, 'Removed context for: $root');
    }
  }

  @override
  Future<void> shutdown() async {
    final contexts = _contexts.values.toList();
    final watchers = _packageConfigWatchers.values.toList();

    _contexts.clear();
    _packageConfigWatchers.clear();
    _staleRoots.clear();

    for (final context in contexts) {
      await context.dispose();
    }
    for (final watcher in watchers) {
      await watcher.cancel();
    }

    await super.shutdown();
  }

  /// Get the current Dart SDK version (major.minor.patch only).
  String? _getCurrentSdkVersion() {
    final versionMatch =
        RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(Platform.version);
    return versionMatch?.group(1);
  }

  /// Start watching package_config.json for changes.
  void _watchPackageConfig(String rootUri, String rootPath) {
    _packageConfigWatchers[rootUri]?.cancel();

    final configPath = '$rootPath/.dart_tool/package_config.json';
    final configFile = File(configPath);

    if (!configFile.existsSync()) return;

    try {
      final watcher = configFile.parent.watch().where((event) {
        return event.path.endsWith('package_config.json');
      }).listen((event) {
        log(
          LoggingLevel.info,
          'package_config.json changed for $rootPath - dependencies may need refresh',
        );
        _staleRoots.add(rootUri);
      });

      _packageConfigWatchers[rootUri] = watcher;
      log(LoggingLevel.debug, 'Watching package_config.json for $rootPath');
    } catch (e) {
      log(LoggingLevel.warning, 'Could not watch package_config.json: $e');
    }
  }

  /// Get or create a CodeContext for the given project path.
  Future<CodeContext?> _getContextForPath(String filePath) async {
    final currentRoots = await roots;

    for (final root in currentRoots) {
      final rootPath = Uri.parse(root.uri).toFilePath();
      if (filePath.startsWith(rootPath)) {
        if (_contexts.containsKey(root.uri)) {
          if (_staleRoots.contains(root.uri)) {
            log(
              LoggingLevel.warning,
              'Dependencies may be out of date. Use dart_refresh to reload.',
            );
          }
          return _contexts[root.uri];
        }

        try {
          log(LoggingLevel.info, 'Creating CodeContext for: ${root.uri}');
          final context = await CodeContext.open(
            rootPath,
            watch: true,
            useCache: useCache,
            loadDependencies: true,
          );
          _contexts[root.uri] = context;

          _watchPackageConfig(root.uri, rootPath);

          final registry = _getRegistry(context);
          final depsInfo = context.hasDependencies && registry != null
              ? ', ${registry.packageIndexes.length} packages loaded'
              : '';
          log(
            LoggingLevel.info,
            'Indexed ${context.stats['files']} files, '
            '${context.stats['symbols']} symbols$depsInfo',
          );

          return context;
        } catch (e) {
          log(LoggingLevel.error, 'Failed to create CodeContext: $e');
          return null;
        }
      }
    }

    return null;
  }

  /// Get context for the first available root.
  Future<CodeContext?> _getDefaultContext() async {
    final currentRoots = await roots;
    if (currentRoots.isEmpty) return null;

    final firstRoot = currentRoots.first;
    final rootPath = Uri.parse(firstRoot.uri).toFilePath();

    if (_contexts.containsKey(firstRoot.uri)) {
      if (_staleRoots.contains(firstRoot.uri)) {
        log(
          LoggingLevel.warning,
          'Dependencies may be out of date. Use dart_refresh to reload.',
        );
      }
      return _contexts[firstRoot.uri];
    }

    try {
      log(LoggingLevel.info, 'Creating CodeContext for: ${firstRoot.uri}');
      final context = await CodeContext.open(
        rootPath,
        watch: true,
        useCache: useCache,
        loadDependencies: true,
      );
      _contexts[firstRoot.uri] = context;

      _watchPackageConfig(firstRoot.uri, rootPath);

      final reg = _getRegistry(context);
      final depsInfo = context.hasDependencies && reg != null
          ? ', ${reg.packageIndexes.length} packages loaded'
          : '';
      log(
        LoggingLevel.info,
        'Indexed ${context.stats['files']} files, '
        '${context.stats['symbols']} symbols$depsInfo',
      );

      return context;
    } catch (e) {
      log(LoggingLevel.error, 'Failed to create CodeContext: $e');
      return null;
    }
  }

  Future<CallToolResult> _handleDartSql(CallToolRequest request) async {
    final sql = request.arguments?['sql'] as String?;
    if (sql == null || sql.isEmpty) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required argument `sql`.')],
        isError: true,
      );
    }

    final format = request.arguments?['format'] as String? ?? 'text';

    // Get context
    final projectHint = request.arguments?['project'] as String?;
    CodeContext? context;

    if (projectHint != null) {
      context = await _getContextForPath(projectHint);
    } else {
      context = await _getDefaultContext();
    }

    if (context == null) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No project found. Make sure roots are set and contain a supported project file (e.g., pubspec.yaml for Dart).',
          ),
        ],
        isError: true,
      );
    }

    try {
      final result = context.sql(sql);
      final output = format == 'json' ? result.toJson(pretty: true) : result.toText();
      return CallToolResult(
        content: [TextContent(text: output)],
        isError: false,
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'SQL error: $e')],
        isError: true,
      );
    }
  }

  Future<CallToolResult> _handleDartSchema(CallToolRequest request) async {
    final projectHint = request.arguments?['project'] as String?;
    CodeContext? context;

    if (projectHint != null) {
      context = await _getContextForPath(projectHint);
    } else {
      context = await _getDefaultContext();
    }

    if (context == null) {
      // Return the schema even without a context (it's always the same)
      return CallToolResult(
        content: [
          TextContent(
            text: '''
## SQL Schema

### symbols
| Column | Type | Description |
|--------|------|-------------|
| scip_id | TEXT PRIMARY KEY | SCIP symbol identifier |
| name | TEXT | Symbol name |
| kind | TEXT | class, method, function, field, enum, etc. |
| file | TEXT | Relative file path (NULL for external) |
| line | INTEGER | Definition line (0-indexed) |
| column_num | INTEGER | Definition column |
| package | TEXT | Package name |
| version | TEXT | Package version |
| container_id | TEXT | Parent symbol SCIP ID |
| display_name | TEXT | Human-readable name |
| documentation | TEXT | Doc comments |
| language | TEXT | Language identifier |

### occurrences
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment ID |
| symbol_id | TEXT | References symbols.scip_id |
| file | TEXT | File path |
| line | INTEGER | Line number (0-indexed) |
| column_num | INTEGER | Column number |
| end_line | INTEGER | End line |
| end_column | INTEGER | End column |
| is_definition | INTEGER | 1 if definition, 0 if reference |
| enclosing_end_line | INTEGER | End of enclosing scope |

### relationships
| Column | Type | Description |
|--------|------|-------------|
| from_symbol | TEXT | Source symbol |
| to_symbol | TEXT | Target symbol |
| kind | TEXT | implements, calls, type_definition, references |

## Common Queries

```sql
-- Find all classes
SELECT name, file, line FROM symbols WHERE kind = 'class';

-- Find symbol definition
SELECT s.name, o.file, o.line 
FROM symbols s 
JOIN occurrences o ON s.scip_id = o.symbol_id 
WHERE s.name = 'MyClass' AND o.is_definition = 1;

-- Find all references
SELECT o.file, o.line, o.column_num 
FROM occurrences o 
JOIN symbols s ON o.symbol_id = s.scip_id 
WHERE s.name = 'login' AND o.is_definition = 0;

-- Get class members
SELECT * FROM symbols 
WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass' LIMIT 1);

-- Find callers of a function
SELECT s.name, s.kind, s.file 
FROM relationships r 
JOIN symbols s ON r.from_symbol = s.scip_id 
WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'login')
  AND r.kind = 'calls';

-- Type hierarchy
SELECT s.name, r.kind 
FROM relationships r 
JOIN symbols s ON r.to_symbol = s.scip_id 
WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'MyWidget')
  AND r.kind = 'implements';
```
''',
          ),
        ],
        isError: false,
      );
    }

    return CallToolResult(
      content: [TextContent(text: context.schema)],
      isError: false,
    );
  }

  /// Handle dart_index_flutter tool.
  Future<CallToolResult> _handleIndexFlutter(CallToolRequest request) async {
    final flutterRoot = request.arguments?['flutterRoot'] as String?;

    final registry = PackageRegistry(rootPath: flutterRoot ?? '.');
    final builder = ExternalIndexBuilder(registry: registry);

    try {
      final result = await builder.indexFlutterPackages(
        flutterPath: flutterRoot,
        onProgress: (msg) => log(LoggingLevel.info, msg),
      );

      if (!result.success) {
        return CallToolResult(
          content: [TextContent(text: 'Failed: ${result.error}')],
          isError: true,
        );
      }

      final output = StringBuffer();
      output.writeln('Flutter ${result.version} indexed successfully');
      output.writeln('');
      output.writeln('Packages indexed: ${result.indexed}');
      output.writeln('Total symbols: ${result.totalSymbols}');
      output.writeln('');
      output.writeln('Results:');
      for (final pkg in result.results) {
        if (pkg.success) {
          output.writeln('  - ${pkg.name}: ${pkg.symbolCount} symbols');
        } else if (pkg.skipped) {
          output.writeln('  - ${pkg.name}: skipped (${pkg.reason})');
        } else {
          output.writeln('  - ${pkg.name}: failed (${pkg.error})');
        }
      }
      output.writeln('');
      output.writeln(
        'Indexes saved to: ${registry.globalCachePath}/flutter/${result.version}/',
      );

      return CallToolResult(
        content: [TextContent(text: output.toString())],
        isError: false,
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error indexing Flutter: $e')],
        isError: true,
      );
    }
  }

  /// Handle dart_index_deps tool.
  Future<CallToolResult> _handleIndexDeps(CallToolRequest request) async {
    final projectHint = request.arguments?['projectRoot'] as String?;

    String projectPath;
    if (projectHint != null) {
      projectPath = projectHint;
    } else {
      final currentRoots = await roots;
      if (currentRoots.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No project roots configured.')],
          isError: true,
        );
      }
      projectPath = Uri.parse(currentRoots.first.uri).toFilePath();
    }

    final lockfile = File('$projectPath/pubspec.lock');
    if (!await lockfile.exists()) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No pubspec.lock found in $projectPath. Run "dart pub get" first.',
          ),
        ],
        isError: true,
      );
    }

    log(LoggingLevel.info, 'Indexing dependencies from $projectPath...');

    final registry = PackageRegistry(rootPath: projectPath);
    final builder = ExternalIndexBuilder(registry: registry);

    try {
      final result = await builder.indexDependencies(
        projectPath,
        onProgress: (msg) => log(LoggingLevel.info, msg),
      );

      if (!result.success) {
        return CallToolResult(
          content: [TextContent(text: 'Failed: ${result.error}')],
          isError: true,
        );
      }

      final output = StringBuffer();
      output.writeln('Dependencies indexed from $projectPath');
      output.writeln('');
      output.writeln('Indexed: ${result.indexed}');
      output.writeln('Skipped (already indexed): ${result.skipped}');
      output.writeln('Failed: ${result.failed}');

      if (result.failed > 0) {
        output.writeln('');
        output.writeln('Failed packages:');
        for (final pkg
            in result.results.where((r) => !r.success && !r.skipped)) {
          output.writeln('  - ${pkg.name}-${pkg.version}: ${pkg.error}');
        }
      }

      return CallToolResult(
        content: [TextContent(text: output.toString())],
        isError: false,
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error indexing dependencies: $e')],
        isError: true,
      );
    }
  }

  /// Handle dart_refresh tool.
  Future<CallToolResult> _handleRefresh(CallToolRequest request) async {
    final projectHint = request.arguments?['projectRoot'] as String?;
    final fullReindex = request.arguments?['fullReindex'] as bool? ?? false;

    final currentRoots = await roots;
    Root? targetRoot;

    if (projectHint != null) {
      for (final root in currentRoots) {
        final rootPath = Uri.parse(root.uri).toFilePath();
        if (rootPath == projectHint || projectHint.startsWith(rootPath)) {
          targetRoot = root;
          break;
        }
      }
    } else if (currentRoots.isNotEmpty) {
      targetRoot = currentRoots.first;
    }

    if (targetRoot == null) {
      return CallToolResult(
        content: [TextContent(text: 'No matching project root found.')],
        isError: true,
      );
    }

    final rootPath = Uri.parse(targetRoot.uri).toFilePath();

    final existingContext = _contexts.remove(targetRoot.uri);
    if (existingContext != null) {
      await existingContext.dispose();
      log(LoggingLevel.info, 'Disposed existing context for $rootPath');
    }
    _staleRoots.remove(targetRoot.uri);

    try {
      log(LoggingLevel.info, 'Refreshing CodeContext for: $rootPath');
      if (fullReindex) {
        log(LoggingLevel.info, 'Full reindex requested (ignoring cache)');
      }
      log(LoggingLevel.info, 'Analyzing project files...');

      final context = await CodeContext.open(
        rootPath,
        binding: DartBinding(),
        watch: true,
        useCache: !fullReindex,
        loadDependencies: true,
      );
      _contexts[targetRoot.uri] = context;

      log(LoggingLevel.info, 'Loading dependencies...');

      _watchPackageConfig(targetRoot.uri, rootPath);

      final refreshRegistry = _getRegistry(context);
      final depsInfo = context.hasDependencies && refreshRegistry != null
          ? ', ${refreshRegistry.packageIndexes.length} packages loaded'
          : '';

      final output = StringBuffer();
      output.writeln('Refreshed: $rootPath');
      output.writeln('Files: ${context.stats['files']}');
      output.writeln('Symbols: ${context.stats['symbols']}');
      if (context.hasDependencies && refreshRegistry != null) {
        output.writeln('Packages: ${refreshRegistry.packageIndexes.length}');
      }

      log(
        LoggingLevel.info,
        'Refreshed ${context.stats['files']} files, '
        '${context.stats['symbols']} symbols$depsInfo',
      );

      return CallToolResult(
        content: [TextContent(text: output.toString())],
        isError: false,
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Error refreshing context: $e')],
        isError: true,
      );
    }
  }

  /// Handle dart_status tool.
  Future<CallToolResult> _handleStatus(CallToolRequest request) async {
    final projectHint = request.arguments?['projectRoot'] as String?;

    CodeContext? context;
    String? rootPath;

    if (projectHint != null) {
      context = await _getContextForPath(projectHint);
      rootPath = projectHint;
    } else {
      final currentRoots = await roots;
      if (currentRoots.isNotEmpty) {
        rootPath = Uri.parse(currentRoots.first.uri).toFilePath();
        if (_contexts.containsKey(currentRoots.first.uri)) {
          context = _contexts[currentRoots.first.uri];
        }
      }
    }

    final output = StringBuffer();
    output.writeln('## Code Context Status (v$dartContextVersion)');
    output.writeln('');

    if (context == null) {
      output.writeln('Project: ${rootPath ?? "(none)"}');
      output.writeln('Status: Not indexed');
      output.writeln('');
      output.writeln('Use dart_sql to trigger indexing, or dart_refresh to reload.');
    } else {
      output.writeln('Project: ${context.rootPath}');
      output.writeln('Files: ${context.stats['files']}');
      output.writeln('Symbols: ${context.stats['symbols']}');
      output.writeln('Occurrences: ${context.stats['occurrences'] ?? 0}');
      output.writeln('Relationships: ${context.stats['relationships'] ?? 0}');
      output.writeln('');

      final registry = _getRegistry(context);
      if (registry != null) {
        final localPkgs = registry.localPackages.keys.toList();
        if (localPkgs.isNotEmpty) {
          output.writeln('### Local Packages (${localPkgs.length})');
          output.writeln('');
          for (final pkg in localPkgs.take(10)) {
            output.writeln('  - $pkg');
          }
          if (localPkgs.length > 10) {
            output.writeln('  ... and ${localPkgs.length - 10} more');
          }
          output.writeln('');
        }
      }

      if (context.hasDependencies && registry != null) {
        output.writeln('### External Indexes');
        output.writeln('');
        if (registry.loadedSdkVersion != null) {
          output.writeln('SDK: Dart ${registry.loadedSdkVersion}');
        }
        if (registry.loadedFlutterVersion != null) {
          output.writeln(
            'Flutter: ${registry.loadedFlutterVersion} (${registry.flutterPackages.length} packages)',
          );
        }

        output.writeln('Hosted packages: ${registry.hostedPackages.length}');
        if (registry.hostedPackages.isNotEmpty) {
          final pkgNames = registry.hostedPackages.keys.take(5).toList();
          for (final name in pkgNames) {
            output.writeln('  - $name');
          }
          if (registry.hostedPackages.length > 5) {
            output.writeln('  ... and ${registry.hostedPackages.length - 5} more');
          }
        }

        if (registry.gitPackages.isNotEmpty) {
          output.writeln('Git packages: ${registry.gitPackages.length}');
          final gitNames = registry.gitPackages.keys.take(5).toList();
          for (final name in gitNames) {
            output.writeln('  - $name');
          }
        }

        if (registry.localIndexes.isNotEmpty) {
          output.writeln('Local packages: ${registry.localIndexes.length}');
          final localNames = registry.localIndexes.keys.take(5).toList();
          for (final name in localNames) {
            output.writeln('  - $name');
          }
        }
      } else if (!context.hasDependencies) {
        output.writeln('External indexes: Not loaded');
        output.writeln(
          'Use dart_index_flutter and dart_index_deps to enable cross-package queries.',
        );
      }
    }

    // Show available indexes on disk
    final tempRegistry = PackageRegistry(rootPath: '.');
    final builder = ExternalIndexBuilder(registry: tempRegistry);

    final sdkVersions = await builder.listSdkIndexes();
    final flutterVersions = await CachePaths.listFlutterVersions();
    final packages = await builder.listPackageIndexes();
    final packageSet = packages.map((p) => p.name).toSet();

    output.writeln('');
    output.writeln('### Available Indexes (on disk)');
    output.writeln('');
    output.writeln(
      'SDK versions: ${sdkVersions.isEmpty ? "(none)" : sdkVersions.join(", ")}',
    );
    output.writeln(
      'Flutter versions: ${flutterVersions.isEmpty ? "(none)" : flutterVersions.join(", ")}',
    );
    output.writeln('Package indexes: ${packages.length}');

    if (rootPath != null) {
      final pubspecFile = File('$rootPath/pubspec.yaml');
      if (await pubspecFile.exists()) {
        final pubspec = await pubspecFile.readAsString();
        final isFlutter =
            pubspec.contains('flutter:') || pubspec.contains('flutter_test:');

        output.writeln('');
        output.writeln('### Recommendations');
        output.writeln('');

        final hasFlutterIndexes = flutterVersions.isNotEmpty;
        if (isFlutter && !hasFlutterIndexes) {
          output.writeln(
            '- Flutter project detected but Flutter SDK not indexed.',
          );
          output.writeln(
            '  Run: `dart_index_flutter` to enable widget hierarchy queries.',
          );
          output.writeln('');
        }

        final lockFile = File('$rootPath/pubspec.lock');
        if (await lockFile.exists()) {
          final lockContent = await lockFile.readAsString();
          final deps = parsePubspecLock(lockContent);
          final missingDeps =
              deps.where((d) => !packageSet.contains(d.name)).toList();

          if (missingDeps.isNotEmpty) {
            output.writeln('- ${missingDeps.length} dependencies not indexed:');
            final toShow = missingDeps.take(5).map((d) => d.name).toList();
            output.writeln(
              '  ${toShow.join(", ")}${missingDeps.length > 5 ? " ..." : ""}',
            );
            output.writeln(
              '  Run: `dart_index_deps` to index all dependencies.',
            );
            output.writeln('');
          } else if (deps.isNotEmpty) {
            output.writeln('- All ${deps.length} dependencies are indexed.');
          }
        } else {
          output.writeln('- No pubspec.lock found. Run `dart pub get` first.');
        }

        if (!isFlutter && sdkVersions.isEmpty) {
          output.writeln('- Dart SDK not indexed. SDK symbols won\'t resolve.');
        }

        if (sdkVersions.isNotEmpty) {
          final currentSdkVersion = _getCurrentSdkVersion();
          if (currentSdkVersion != null &&
              !sdkVersions.contains(currentSdkVersion)) {
            output.writeln(
              '- Current SDK ($currentSdkVersion) differs from indexed: ${sdkVersions.join(", ")}',
            );
            output.writeln('  Consider re-indexing for accurate results.');
          }
        }
      }
    }

    return CallToolResult(
      content: [TextContent(text: output.toString())],
      isError: false,
    );
  }

  /// The dart_sql tool definition.
  static final dartSqlTool = Tool(
    name: 'dart_sql',
    description: '''Execute SQL queries against the Dart code index.

## Schema

Three tables are available:
- `symbols` - Symbol definitions (classes, methods, functions, fields, etc.)
- `occurrences` - Where symbols are defined and referenced
- `relationships` - Type hierarchy and call graph edges

### symbols columns
scip_id, name, kind, file, line, column_num, package, version, container_id, display_name, documentation, language

### occurrences columns
id, symbol_id, file, line, column_num, end_line, end_column, is_definition, enclosing_end_line

### relationships columns
from_symbol, to_symbol, kind (implements, calls, type_definition, references)

## Example Queries

```sql
-- Find all classes
SELECT name, file, line FROM symbols WHERE kind = 'class';

-- Find symbol definition
SELECT s.name, o.file, o.line 
FROM symbols s 
JOIN occurrences o ON s.scip_id = o.symbol_id 
WHERE s.name = 'MyClass' AND o.is_definition = 1;

-- Find all references
SELECT o.file, o.line 
FROM occurrences o 
JOIN symbols s ON o.symbol_id = s.scip_id 
WHERE s.name = 'login' AND o.is_definition = 0;

-- Get class members
SELECT * FROM symbols 
WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass' LIMIT 1);

-- Find callers
SELECT s.name, s.file 
FROM relationships r 
JOIN symbols s ON r.from_symbol = s.scip_id 
WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'login')
  AND r.kind = 'calls';

-- Pattern matching
SELECT name, kind FROM symbols WHERE name GLOB '*Service*';
```

Kinds: class, method, function, field, enum, mixin, extension, getter, setter, constructor, parameter, variable
''',
    annotations: ToolAnnotations(
      title: 'Dart SQL Query',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'sql': Schema.string(
          description: 'SQL query to execute. Only SELECT queries are allowed.',
        ),
        'format': Schema.string(
          description: 'Output format: "text" (default, markdown table) or "json"',
        ),
        'project': Schema.string(
          description: 'Optional path hint to select which project root to query.',
        ),
      },
      required: ['sql'],
    ),
  );

  /// The dart_schema tool definition.
  static final dartSchemaTool = Tool(
    name: 'dart_schema',
    description: 'Show the SQL schema and example queries for the code index.',
    annotations: ToolAnnotations(
      title: 'Show Schema',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'project': Schema.string(
          description: 'Optional path hint to select project.',
        ),
      },
    ),
  );

  /// Tool to index Flutter SDK packages.
  static final dartIndexFlutterTool = Tool(
    name: 'dart_index_flutter',
    description: '''Index Flutter SDK packages for cross-package queries.

One-time setup that indexes flutter, flutter_test, flutter_driver, flutter_localizations, and flutter_web_plugins.

After indexing, SQL queries can search across your project and Flutter SDK.

Takes ~1 minute for a typical Flutter SDK.''',
    annotations: ToolAnnotations(
      title: 'Index Flutter SDK',
      readOnlyHint: false,
    ),
    inputSchema: Schema.object(
      properties: {
        'flutterRoot': Schema.string(
          description:
              'Path to Flutter SDK root. If not provided, uses FLUTTER_ROOT env var or finds from PATH.',
        ),
      },
    ),
  );

  /// Tool to index pub dependencies.
  static final dartIndexDepsTool = Tool(
    name: 'dart_index_deps',
    description: '''Index pub dependencies from pubspec.lock.

Pre-indexes all packages listed in pubspec.lock for cross-package queries. Skips packages already indexed.

Run this after adding new dependencies or when setting up a new project.

Takes ~1-2 minutes for typical projects.''',
    annotations: ToolAnnotations(
      title: 'Index Dependencies',
      readOnlyHint: false,
    ),
    inputSchema: Schema.object(
      properties: {
        'projectRoot': Schema.string(
          description:
              'Path to project with pubspec.lock. If not provided, uses the first configured root.',
        ),
      },
    ),
  );

  /// Tool to refresh project index.
  static final dartRefreshTool = Tool(
    name: 'dart_refresh',
    description: '''Refresh project index and reload dependencies.

Use after:
- pubspec.yaml or pubspec.lock changes
- Major refactoring
- When you suspect the index is stale

Set fullReindex=true to ignore cache and rebuild from scratch.''',
    annotations: ToolAnnotations(
      title: 'Refresh Index',
      readOnlyHint: false,
    ),
    inputSchema: Schema.object(
      properties: {
        'projectRoot': Schema.string(
          description: 'Path to project. If not provided, uses the first configured root.',
        ),
        'fullReindex': Schema.bool(
          description: 'Force full re-index, ignoring cache. Default: false.',
        ),
      },
    ),
  );

  /// Tool to show index status.
  static final dartStatusTool = Tool(
    name: 'dart_status',
    description: '''Show index status: files, symbols, loaded packages, SDK version.

Displays:
- Project index statistics (files, symbols, occurrences, relationships)
- Loaded external packages
- Available pre-computed indexes on disk

Use to verify indexing is complete before querying.''',
    annotations: ToolAnnotations(
      title: 'Index Status',
      readOnlyHint: true,
    ),
    inputSchema: Schema.object(
      properties: {
        'projectRoot': Schema.string(
          description: 'Path to project. If not provided, uses the first configured root.',
        ),
      },
    ),
  );
}
