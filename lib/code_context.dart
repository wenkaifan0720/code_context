/// Language-agnostic semantic code intelligence with SQL queries.
///
/// Query your codebase with SQL:
/// ```dart
/// // Auto-detect language from project files
/// final context = await CodeContext.open('/path/to/project');
///
/// // Or specify a binding explicitly
/// final context = await CodeContext.open(
///   '/path/to/project',
///   binding: DartBinding(),
/// );
///
/// // Find all classes
/// final result = context.sql("SELECT * FROM symbols WHERE kind = 'class'");
///
/// // Find symbol definition
/// final result = context.sql('''
///   SELECT s.name, o.file, o.line
///   FROM symbols s
///   JOIN occurrences o ON s.scip_id = o.symbol_id
///   WHERE s.name = 'AuthRepository' AND o.is_definition = 1
/// ''');
///
/// // Load dependencies for cross-package queries
/// await context.loadDependencies();
///
/// // Query across packages
/// final result = context.sql("SELECT * FROM symbols WHERE name GLOB '*Widget*'");
/// ```
///
/// ## SQL Schema
///
/// - `symbols` - Symbol definitions (classes, methods, functions, etc.)
/// - `occurrences` - Where symbols are defined and referenced
/// - `relationships` - Type hierarchy and call graph
///
/// ## Supported Languages
///
/// - Dart (via `DartBinding` from `dart_binding` package)
/// - More languages coming soon...
///
/// ## Works with any folder structure
///
/// The unified architecture works for:
/// - Single packages
/// - Melos mono repos
/// - Dart pub workspaces
/// - Any folder with multiple packages
library;

// Main entry point
export 'src/code_context.dart';

// Re-export scip_server package (language-agnostic core)
export 'package:scip_server/scip_server.dart'
    show
        // Index types
        ScipIndex,
        SymbolInfo,
        OccurrenceInfo,
        RelationshipInfo,
        GrepMatchData,
        // SQL types
        SqlIndex,
        SqlExecutor,
        SqlResult,
        SqlExecutionError,
        ScipToSql,
        // Language binding
        LanguageBinding,
        LanguageContext,
        DiscoveredPackage,
        PackageIndexer,
        IndexUpdate,
        InitialIndexUpdate,
        FileUpdatedUpdate,
        FileRemovedUpdate,
        IndexErrorUpdate,
        // Protocol server
        ScipServer,
        ScipMethod,
        JsonRpcRequest,
        JsonRpcResponse,
        JsonRpcError,
        SqlResponse,
        SqlParams,
        InitializeParams,
        InitializeResult,
        FileChangeParams,
        StatusResult;

// Re-export dart_binding package (Dart-specific)
export 'package:dart_binding/dart_binding.dart'
    show
        // Main binding
        DartBinding,
        DartLanguageContext,
        DartPackageIndexer,
        RootWatcher,
        // Indexing
        IncrementalScipIndexer,
        IndexCache,
        ExternalIndexBuilder,
        IndexResult,
        BatchIndexResult,
        PackageIndexResult,
        FlutterIndexResult,
        CachedIndexUpdate,
        IncrementalIndexUpdate,
        // Package management
        PackageRegistry,
        LocalPackageIndex,
        ExternalPackageIndex,
        ExternalPackageType,
        DependencyLoadResult,
        IndexScope,
        // Discovery
        LocalPackage,
        DiscoveryResult,
        PackageDiscovery,
        // Cache
        CachePaths,
        // Adapters
        AnalyzerAdapter,
        FileChange,
        FileChangeType,
        HologramAnalyzerAdapter,
        // Utilities
        DependencySource,
        ResolvedPackage,
        parsePackageConfig,
        parsePackageConfigSync,
        parsePubspecLock,
        dartContextVersion,
        manifestVersion;

// ─────────────────────────────────────────────────────────────────────────────
// Architecture Notes
// ─────────────────────────────────────────────────────────────────────────────

// This package is structured as follows:
//
// packages/
// ├── scip_server/              # Language-agnostic SCIP query engine with SQL
// │   ├── ScipIndex             # In-memory SCIP protobuf representation
// │   ├── SqlIndex              # SQLite database for queries
// │   ├── ScipToSql             # SCIP → SQL converter
// │   ├── SqlExecutor           # SQL query execution
// │   ├── LanguageBinding       # Interface for language implementations
// │   ├── LanguageContext       # Abstract context interface
// │   └── ScipServer            # JSON-RPC protocol server
// │
// └── dart_binding/             # Dart-specific implementation
//     ├── DartBinding           # LanguageBinding implementation
//     ├── DartLanguageContext   # LanguageContext implementation
//     ├── IncrementalScipIndexer # Incremental Dart indexer
//     ├── PackageRegistry       # Multi-package management
//     └── PackageDiscovery      # Pubspec.yaml discovery
//
// The root package (code_context) provides:
// - CodeContext: High-level API using LanguageBinding + SQL
// - MCP server integration
