import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:code_context/code_context.dart';

void main(List<String> arguments) async {
  // Register language bindings for auto-detection
  CodeContext.registerBinding(DartBinding());

  // Check for subcommands first
  if (arguments.isNotEmpty) {
    final cmd = arguments.first;

    // Generic commands
    switch (cmd) {
      case 'list-packages':
        await _listPackages(arguments.skip(1).toList());
        return;
      case 'schema':
        _printSchema();
        return;
    }

    // Dart-specific commands (dart: prefix)
    if (cmd.startsWith('dart:')) {
      final dartCmd = cmd.substring(5);
      switch (dartCmd) {
        case 'index-sdk':
          await _dartIndexSdk(arguments.skip(1).toList());
          return;
        case 'index-flutter':
          await _dartIndexFlutter(arguments.skip(1).toList());
          return;
        case 'index-deps':
          await _dartIndexDependencies(arguments.skip(1).toList());
          return;
        case 'list-indexes':
          await _dartListIndexes();
          return;
        default:
          stderr.writeln('Unknown Dart command: dart:$dartCmd');
          stderr.writeln('');
          stderr.writeln('Available Dart commands:');
          stderr.writeln('  dart:index-sdk      Index Dart SDK');
          stderr.writeln('  dart:index-flutter  Index Flutter packages');
          stderr.writeln('  dart:index-deps     Index pub dependencies');
          stderr.writeln('  dart:list-indexes   List available indexes');
          exit(1);
      }
    }
  }

  final parser = ArgParser()
    ..addOption(
      'project',
      abbr: 'p',
      help: 'Path to the project (defaults to current directory)',
      defaultsTo: '.',
    )
    ..addOption(
      'format',
      abbr: 'f',
      help: 'Output format: text or json',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
    )
    ..addFlag(
      'watch',
      abbr: 'w',
      help: 'Watch for file changes and show updates',
      defaultsTo: false,
    )
    ..addFlag(
      'interactive',
      abbr: 'i',
      help: 'Run in interactive SQL REPL mode',
      defaultsTo: false,
    )
    ..addFlag(
      'no-cache',
      help: 'Disable cache and force full re-index',
      defaultsTo: false,
    )
    ..addFlag(
      'with-deps',
      help: 'Load pre-indexed dependencies for cross-package queries',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: $e');
    _printUsage(parser);
    exit(1);
  }

  if (args['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  final projectPath = args['project'] as String;
  final format = args['format'] as String;
  final watch = args['watch'] as bool;
  final interactive = args['interactive'] as bool;
  final noCache = args['no-cache'] as bool;
  final withDeps = args['with-deps'] as bool;

  // Check for supported project
  final isDartProject = await File('$projectPath/pubspec.yaml').exists() ||
      (await PackageDiscovery().discoverPackages(projectPath))
          .packages
          .isNotEmpty;

  if (!isDartProject) {
    stderr.writeln('Error: No supported project found in $projectPath');
    stderr.writeln('Supported languages: Dart (pubspec.yaml)');
    exit(1);
  }

  stderr.writeln('Opening project: $projectPath');
  if (withDeps) {
    stderr.writeln('Loading pre-indexed dependencies...');
  }

  CodeContext? context;
  try {
    final stopwatch = Stopwatch()..start();
    context = await CodeContext.open(
      projectPath,
      binding: DartBinding(),
      watch: watch || interactive,
      useCache: !noCache,
      loadDependencies: withDeps,
    );
    stopwatch.stop();

    final pkgCount = context.packageCount;
    final pkgInfo = pkgCount > 1 ? ' across $pkgCount packages' : '';
    final registry = _getRegistry(context);
    final depsInfo = withDeps && context.hasDependencies && registry != null
        ? ', ${registry.packageIndexes.length} external packages loaded'
        : '';
    stderr.writeln(
      'Indexed ${context.stats['files']} files, '
      '${context.stats['symbols']} symbols$pkgInfo'
      '$depsInfo '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    if (interactive) {
      await _runInteractive(context, format);
    } else if (watch) {
      final sql = args.rest.isNotEmpty ? args.rest.join(' ') : null;
      await _runWatch(context, format, sql);
    } else if (args.rest.isEmpty) {
      // No query provided, show stats
      final stats = context.stats;
      stdout.writeln('Index Statistics:');
      stdout.writeln('  Files: ${stats['files']}');
      stdout.writeln('  Symbols: ${stats['symbols']}');
      stdout.writeln('  Occurrences: ${stats['occurrences']}');
      stdout.writeln('  Relationships: ${stats['relationships']}');
      stdout.writeln('  Packages: ${stats['packages']}');
    } else {
      // Execute the SQL query from command line
      final sql = args.rest.join(' ');
      final result = context.sql(sql);
      _printResult(result, format);
    }
  } catch (e, st) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] != null) {
      stderr.writeln(st);
    }
    exit(1);
  } finally {
    await context?.dispose();
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('code_context - Semantic code intelligence with SQL queries');
  stdout.writeln('');
  stdout.writeln('Usage: code_context [options] <sql-query>');
  stdout.writeln('       code_context <subcommand> [args]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Subcommands:');
  stdout.writeln('  list-packages [path]   List discovered packages');
  stdout.writeln('  schema                 Show SQL schema');
  stdout.writeln('');
  stdout.writeln('Dart-specific commands:');
  stdout.writeln('  dart:index-sdk <path>  Pre-index the Dart SDK');
  stdout.writeln('  dart:index-flutter     Pre-index Flutter packages');
  stdout.writeln('  dart:index-deps        Pre-index pub dependencies');
  stdout.writeln('  dart:list-indexes      List available Dart indexes');
  stdout.writeln('');
  stdout.writeln('SQL Schema:');
  stdout.writeln(
      '  symbols      - Symbol definitions (scip_id, name, kind, file, line, ...)');
  stdout.writeln(
      '  occurrences  - References and definitions (symbol_id, file, line, is_definition, ...)');
  stdout.writeln(
      '  relationships - Hierarchy and calls (from_symbol, to_symbol, kind)');
  stdout.writeln('');
  stdout.writeln('Example Queries:');
  stdout
      .writeln("  code_context \"SELECT * FROM symbols WHERE kind = 'class'\"");
  stdout.writeln(
      "  code_context \"SELECT name, file FROM symbols WHERE name GLOB '*Service*'\"");
  stdout.writeln(
      '  code_context "SELECT o.file, o.line FROM occurrences o JOIN symbols s ON o.symbol_id = s.scip_id WHERE s.name = \'login\' AND o.is_definition = 0"');
  stdout.writeln('');
  stdout.writeln('Interactive mode:');
  stdout.writeln('  code_context -i                # Start SQL REPL');
  stdout.writeln('');
  stdout.writeln('Cross-package queries:');
  stdout.writeln('  code_context dart:index-deps   # Index dependencies first');
  stdout.writeln(
      '  code_context --with-deps "SELECT * FROM symbols WHERE name = \'StatelessWidget\'"');
}

void _printSchema() {
  stdout.writeln('''
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

-- Pattern matching
SELECT name, kind FROM symbols WHERE name GLOB '*Service*';
```
''');
}

void _printResult(SqlResult result, String format) {
  if (format == 'json') {
    stdout.writeln(result.toJson(pretty: true));
  } else {
    stdout.writeln(result.toText());
  }
}

/// Get the Dart registry from a context (Dart-specific).
PackageRegistry? _getRegistry(CodeContext context) {
  final langContext = context.context;
  if (langContext is DartLanguageContext) {
    return langContext.registry;
  }
  return null;
}

Future<void> _runWatch(
  CodeContext context,
  String format,
  String? sql,
) async {
  // Run initial query if provided
  if (sql != null) {
    final result = context.sql(sql);
    _printResult(result, format);
    stdout.writeln('');
  }

  stderr.writeln('Watching for changes... (Ctrl+C to stop)');
  stderr.writeln('');

  final completer = Completer<void>();

  late StreamSubscription<ProcessSignal> sigintSubscription;
  sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
    stderr.writeln('');
    stderr.writeln('Stopping watch...');
    sigintSubscription.cancel();
    completer.complete();
  });

  final subscription = context.updates.listen((update) async {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);

    if (update is FileUpdatedUpdate) {
      stderr.writeln('[$timestamp] Updated: ${update.path}');
      context.rebuildSqlIndex();

      if (sql != null) {
        final result = context.sql(sql);
        stdout.writeln('');
        _printResult(result, format);
      }
    } else if (update is FileRemovedUpdate) {
      stderr.writeln('[$timestamp] Removed: ${update.path}');
      context.rebuildSqlIndex();

      if (sql != null) {
        final result = context.sql(sql);
        stdout.writeln('');
        _printResult(result, format);
      }
    } else if (update is IndexErrorUpdate) {
      stderr.writeln('[$timestamp] Error: ${update.path} - ${update.message}');
    }
  });

  try {
    await completer.future;
  } finally {
    await subscription.cancel();
  }

  stderr.writeln('Watch mode stopped.');
}

Future<void> _runInteractive(CodeContext context, String format) async {
  stdout.writeln('');
  stdout.writeln('SQL REPL mode. Commands:');
  stdout.writeln('  .schema    Show table schema');
  stdout.writeln('  .tables    List tables');
  stdout.writeln('  .stats     Show index statistics');
  stdout.writeln('  .refresh   Refresh index from source files');
  stdout.writeln('  .quit      Exit');
  stdout.writeln('');

  final subscription = context.updates.listen((update) {
    stderr.writeln('  [update] $update');
  });

  try {
    while (true) {
      stdout.write('sql> ');
      final line = stdin.readLineSync();

      if (line == null || line == '.quit' || line == '.exit') {
        break;
      }

      if (line.isEmpty) continue;

      // Handle special commands
      if (line.startsWith('.')) {
        switch (line) {
          case '.schema':
            _printSchema();
            continue;
          case '.tables':
            stdout.writeln('Tables: symbols, occurrences, relationships');
            continue;
          case '.stats':
            final stats = context.stats;
            stdout.writeln('Symbols: ${stats['symbols']}');
            stdout.writeln('Occurrences: ${stats['occurrences']}');
            stdout.writeln('Relationships: ${stats['relationships']}');
            continue;
          case '.refresh':
            stderr.writeln('Refreshing...');
            await context.refreshAll();
            context.rebuildSqlIndex();
            stderr
                .writeln('Done. ${context.stats['symbols']} symbols indexed.');
            continue;
          default:
            stderr.writeln('Unknown command: $line');
            continue;
        }
      }

      try {
        final result = context.sql(line);
        _printResult(result, format);
      } catch (e) {
        stderr.writeln('Error: $e');
      }
      stdout.writeln('');
    }
  } finally {
    await subscription.cancel();
  }

  stdout.writeln('Goodbye!');
}

// ─────────────────────────────────────────────────────────────────────────────
// Dart-specific commands (dart: prefix)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _dartIndexSdk(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: code_context dart:index-sdk <sdk-path>');
    stderr.writeln('');
    stderr.writeln('Example:');
    stderr.writeln(
        '  code_context dart:index-sdk /opt/flutter/bin/cache/dart-sdk');
    exit(1);
  }

  final sdkPath = args.first;
  final sdkDir = Directory(sdkPath);

  if (!await sdkDir.exists()) {
    stderr.writeln('Error: SDK path does not exist: $sdkPath');
    exit(1);
  }

  final versionFile = File('$sdkPath/version');
  if (!await versionFile.exists()) {
    stderr.writeln('Error: Not a valid Dart SDK (no version file found)');
    exit(1);
  }

  final version = (await versionFile.readAsString()).trim();
  stderr.writeln('Indexing Dart SDK $version...');

  final registry = PackageRegistry(rootPath: sdkPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  final result = await builder.indexSdk(sdkPath);
  stopwatch.stop();

  if (result.success) {
    stdout.writeln('SDK indexed successfully');
    stdout.writeln('  Version: ${result.stats?['version']}');
    stdout.writeln('  Symbols: ${result.stats?['symbols']}');
    stdout.writeln('  Files: ${result.stats?['files']}');
    stdout.writeln('  Time: ${stopwatch.elapsed.inSeconds}s');
    stdout.writeln('');
    stdout.writeln('Index saved to: ${CachePaths.sdkDir(version)}');
  } else {
    stderr.writeln('Failed to index SDK: ${result.error}');
    exit(1);
  }
}

Future<void> _dartIndexFlutter(List<String> args) async {
  String? flutterPath;
  if (args.isNotEmpty) {
    flutterPath = args.first;
  } else {
    flutterPath = Platform.environment['FLUTTER_ROOT'];
    if (flutterPath == null) {
      try {
        final result = await Process.run('which', ['flutter']);
        if (result.exitCode == 0) {
          final flutterBin = result.stdout.toString().trim();
          flutterPath = Directory(flutterBin).parent.parent.path;
        }
      } catch (_) {}
    }
  }

  if (flutterPath == null || !await Directory(flutterPath).exists()) {
    stderr.writeln('Usage: code_context dart:index-flutter [flutter-path]');
    stderr.writeln('');
    stderr.writeln('If no path is provided, uses FLUTTER_ROOT or PATH.');
    exit(1);
  }

  final packagesPath = '$flutterPath/packages';
  if (!await Directory(packagesPath).exists()) {
    stderr.writeln('Error: Flutter packages not found at $packagesPath');
    exit(1);
  }

  // Get Flutter version using flutter --version --machine
  String version = 'unknown';
  try {
    final result = await Process.run(
      '$flutterPath/bin/flutter',
      ['--version', '--machine'],
    );
    if (result.exitCode == 0) {
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      version = json['frameworkVersion'] as String? ?? 'unknown';
    }
  } catch (_) {
    // Fall back to version file
    final versionFile = File('$flutterPath/version');
    if (await versionFile.exists()) {
      version = (await versionFile.readAsString()).trim();
    }
  }

  stderr.writeln('Indexing Flutter $version packages...');
  stderr.writeln('Path: $flutterPath');

  final flutterPackages = [
    'flutter',
    'flutter_test',
    'flutter_driver',
    'flutter_localizations',
    'flutter_web_plugins',
  ];

  final registry = PackageRegistry(rootPath: flutterPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  var successCount = 0;
  var failCount = 0;

  for (final pkgName in flutterPackages) {
    final pkgPath = '$packagesPath/$pkgName';
    if (!await Directory(pkgPath).exists()) {
      stderr.writeln('  Skipping $pkgName (not found)');
      continue;
    }

    final pkgConfigFile = File('$pkgPath/.dart_tool/package_config.json');
    if (!await pkgConfigFile.exists()) {
      stderr.writeln('  Running flutter pub get in $pkgName...');
      final result = await Process.run(
        'flutter',
        ['pub', 'get'],
        workingDirectory: pkgPath,
      );
      if (result.exitCode != 0) {
        stderr.writeln('  Failed to get dependencies for $pkgName');
        failCount++;
        continue;
      }
    }

    stderr.write('  Indexing $pkgName... ');
    final result = await builder.indexFlutterPackage(
      pkgName,
      version,
      pkgPath,
    );

    if (result.success) {
      stdout.writeln('done (${result.stats?['symbols']} symbols)');
      successCount++;
    } else {
      stdout.writeln('failed: ${result.error}');
      failCount++;
    }
  }

  stopwatch.stop();
  stdout.writeln('');
  stdout.writeln('Indexed: $successCount packages');
  stdout.writeln('Failed: $failCount packages');
  stdout.writeln('Time: ${stopwatch.elapsed.inSeconds}s');
  stdout.writeln('');
  stdout.writeln(
      'Indexes saved to: ${CachePaths.globalCacheDir}/flutter/$version/');
}

Future<void> _dartIndexDependencies(List<String> args) async {
  final projectPath = args.isNotEmpty ? args.first : '.';

  final lockfile = File('$projectPath/pubspec.lock');
  if (!await lockfile.exists()) {
    stderr.writeln('Error: No pubspec.lock found in $projectPath');
    stderr.writeln('Run "dart pub get" first.');
    exit(1);
  }

  stderr.writeln('Indexing dependencies from $projectPath...');

  final registry = PackageRegistry(rootPath: projectPath);
  final builder = ExternalIndexBuilder(registry: registry);

  final stopwatch = Stopwatch()..start();
  final result = await builder.indexDependencies(projectPath);
  stopwatch.stop();

  if (!result.success) {
    stderr.writeln('Failed: ${result.error}');
    exit(1);
  }

  stdout.writeln('Indexed: ${result.indexed}');
  stdout.writeln('Skipped: ${result.skipped}');
  stdout.writeln('Failed: ${result.failed}');
  stdout.writeln('Time: ${stopwatch.elapsed.inSeconds}s');

  if (result.failed > 0) {
    stdout.writeln('');
    stdout.writeln('Failed packages:');
    for (final pkg in result.results.where((r) => !r.success && !r.skipped)) {
      stdout.writeln('  - ${pkg.name}-${pkg.version}: ${pkg.error}');
    }
  }
}

Future<void> _dartListIndexes() async {
  final registry = PackageRegistry(rootPath: '.');
  final builder = ExternalIndexBuilder(registry: registry);

  stdout.writeln('Pre-computed Dart indexes in ${CachePaths.globalCacheDir}:');
  stdout.writeln('');

  final sdkVersions = await builder.listSdkIndexes();
  stdout.writeln('SDK Indexes:');
  if (sdkVersions.isEmpty) {
    stdout.writeln('  (none)');
  } else {
    for (final version in sdkVersions) {
      stdout.writeln('  - Dart SDK $version');
    }
  }
  stdout.writeln('');

  final flutterDir = Directory('${CachePaths.globalCacheDir}/flutter');
  stdout.writeln('Flutter Indexes:');
  if (await flutterDir.exists()) {
    final versions = await flutterDir
        .list()
        .where((e) => e is Directory)
        .map((e) => e.path.split('/').last)
        .toList();
    if (versions.isEmpty) {
      stdout.writeln('  (none)');
    } else {
      for (final version in versions) {
        final pkgDir = Directory('${flutterDir.path}/$version');
        final packages = await pkgDir
            .list()
            .where((e) => e is Directory)
            .map((e) => e.path.split('/').last)
            .toList();
        stdout.writeln('  - Flutter $version (${packages.length} packages)');
      }
    }
  } else {
    stdout.writeln('  (none)');
  }
  stdout.writeln('');

  final packages = await builder.listPackageIndexes();
  stdout.writeln('Hosted Package Indexes:');
  if (packages.isEmpty) {
    stdout.writeln('  (none)');
  } else {
    for (final pkg in packages) {
      stdout.writeln('  - ${pkg.name} ${pkg.version}');
    }
  }
  stdout.writeln('');

  final gitDir = Directory('${CachePaths.globalCacheDir}/git');
  stdout.writeln('Git Package Indexes:');
  if (await gitDir.exists()) {
    final gitPackages = await gitDir
        .list()
        .where((e) => e is Directory)
        .map((e) => e.path.split('/').last)
        .toList();
    if (gitPackages.isEmpty) {
      stdout.writeln('  (none)');
    } else {
      for (final pkg in gitPackages) {
        stdout.writeln('  - $pkg');
      }
    }
  } else {
    stdout.writeln('  (none)');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic commands
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _listPackages(List<String> args) async {
  final path = args.isNotEmpty ? args.first : '.';

  stderr.writeln('Discovering packages in $path...');

  final stopwatch = Stopwatch()..start();

  for (final binding in CodeContext.registeredBindings) {
    final packages = await binding.discoverPackages(path);
    if (packages.isNotEmpty) {
      stopwatch.stop();
      stdout.writeln('');
      stdout.writeln(
          'Found ${packages.length} ${binding.languageId} packages in ${stopwatch.elapsedMilliseconds}ms:');
      stdout.writeln('');

      for (final pkg in packages) {
        final cacheDir = '${pkg.path}/.${binding.languageId}_context';
        final hasCache = await Directory(cacheDir).exists();
        final cacheStatus = hasCache ? 'indexed' : 'not indexed';
        stdout.writeln('  ${pkg.name} ($cacheStatus)');
        stdout.writeln('    Path: ${pkg.path}');
      }
      return;
    }
  }

  stopwatch.stop();
  stdout.writeln('');
  stdout.writeln('No packages found in $path');
}
