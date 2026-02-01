# Architecture

## Overview

code_context provides lightweight semantic code intelligence with multi-language support. It uses SCIP (Semantic Code Intelligence Protocol) for standardized code indexing and SQLite for query execution.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CodeContext                                   │
│  Entry point: open(), sql(), dispose()                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────┐│
│  │ LLM / Agent  │────▶│  SQL Query   │────▶│     SqlExecutor          ││
│  │              │     │ SELECT ...   │     │                          ││
│  └──────────────┘     └──────────────┘     │  execute() → SqlResult   ││
│                                            └────────────┬─────────────┘│
│                                                         │              │
│                                                         ▼              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      SqlIndex (SQLite)                           │  │
│  │  Tables: symbols, occurrences, relationships                     │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                    ▲                                   │
│                                    │ (loads from)                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     LanguageBinding                              │  │
│  │  Dart (DartBinding) | TypeScript (future) | Python (future)     │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│              ┌───────────────────┼───────────────────┐                 │
│              ▼                   ▼                   ▼                 │
│  ┌───────────────────┐  ┌───────────────┐  ┌────────────────────────┐ │
│  │ LocalPackageIndex │  │ ScipIndex     │  │ ExternalPackageIndex   │ │
│  │ + Indexer (live)  │  │ (in-memory)   │  │ SDK/Flutter/pub (cached)│ │
│  └───────────────────┘  └───────────────┘  └────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Package Structure (Monorepo)

The project is organized as a Dart pub workspace:

```
code_context/
├── packages/
│   ├── scip_server/          # Language-agnostic SCIP protocol core
│   │   ├── lib/src/
│   │   │   ├── index/        # ScipIndex (in-memory SCIP storage)
│   │   │   ├── sql/          # SqlIndex, SqlExecutor, ScipToSql
│   │   │   ├── protocol/     # JSON-RPC protocol layer
│   │   │   └── language_binding.dart
│   │   └── pubspec.yaml
│   │
│   ├── dart_binding/         # Dart-specific implementation
│   │   ├── lib/src/
│   │   │   ├── adapters/     # Analyzer adapters (bring your own analyzer)
│   │   │   ├── cache/        # Cache path management
│   │   │   └── ...           # Incremental indexer, package discovery
│   │   └── pubspec.yaml
│   │
│   └── scip_dart/            # Local fork of scip-dart indexer
│       └── lib/src/          # SCIP visitor, symbol generator
│
├── lib/                      # Root package (code_context)
│   ├── code_context.dart     # Re-exports for public API
│   └── src/
│       ├── code_context.dart # Main CodeContext class
│       └── mcp/              # MCP server support
│
├── bin/
│   ├── code_context.dart     # CLI entry point
│   └── mcp_server.dart       # MCP server entry point
│
└── pubspec.yaml              # Workspace root
```

## Core Components

### scip_server (Language-Agnostic)

| Component | Description |
|-----------|-------------|
| `ScipIndex` | In-memory SCIP index with O(1) symbol lookups |
| `SqlIndex` | SQLite database wrapper for query execution |
| `SqlExecutor` | Executes SQL queries and formats results |
| `ScipToSql` | Converts SCIP data to SQL tables |
| `LanguageBinding` | Interface for language-specific implementations |
| `LanguageContext` | Abstract runtime context per language |

### dart_binding (Dart-Specific)

| Component | Description |
|-----------|-------------|
| `DartBinding` | Implements `LanguageBinding` for Dart |
| `DartLanguageContext` | Dart-specific `LanguageContext` implementation |
| `IncrementalScipIndexer` | File-watching incremental indexer |
| `PackageRegistry` | Manages local + external package indexes |
| `PackageDiscovery` | Discovers packages in monorepos |
| `ExternalIndexBuilder` | Pre-computes indexes for SDK/dependencies |
| `AnalyzerAdapter` | Interface for bringing your own analyzer |

## How It Works

### Initialization Flow

1. **Register Bindings**: `CodeContext.registerBinding(DartBinding())`
2. **Auto-Detection**: `CodeContext.open()` detects language from project files
3. **Create Context**: Binding creates a `LanguageContext` with indexer and registry
4. **Build SQL Index**: SCIP data is loaded into SQLite for querying

### Indexing Flow

1. **Cache Check**: On open, looks for valid cache in `.dart_context/` directory
2. **Initial/Incremental Index**: Full scan if no cache, or only changed files if cache exists
3. **File Watching**: Uses filesystem events to detect changes
4. **Incremental Updates**: Only re-analyzes changed files (via SHA-256 hash comparison)
5. **Cache Persistence**: Saves index to disk after updates for fast subsequent startups
6. **SQL Rebuild**: SQLite database is rebuilt when SCIP index changes

### Query Flow

1. **Receive SQL**: SQL query string from user/agent
2. **Validate**: Only SELECT queries allowed (read-only enforcement)
3. **Execute**: SQLite executes the query
4. **Format**: Results formatted as Markdown table or JSON

### Caching

The SCIP index is cached in `.dart_context/` within each package:

```
your_project/
└── .dart_context/
    ├── index.scip         # Serialized SCIP protobuf index
    └── manifest.json      # File hashes for cache validation
```

Global pre-computed indexes are stored in `~/.dart_context/`:

```
~/.dart_context/
├── sdk/
│   └── 3.7.1/index.scip              # Dart SDK (versioned)
├── flutter/
│   └── 3.32.0/flutter/index.scip     # Flutter packages
├── hosted/
│   ├── collection-1.18.0/index.scip  # Pub packages
│   └── analyzer-6.3.0/index.scip
└── git/
    └── fluxon-bfef6c5e/index.scip    # Git dependencies
```

Note: The SQLite database is built in-memory on startup from these cached SCIP files. This keeps storage minimal while enabling fast SQL queries.

## Bringing Your Own Analyzer

For IDE integration (e.g., Hologram), you can provide your own analyzer:

```dart
import 'package:dart_binding/dart_binding.dart';

// Create adapter wrapping your analyzer
final adapter = HologramAnalyzerAdapter(
  projectRoot: myAnalyzer.projectRoot,
  getResolvedUnit: (path) => myAnalyzer.getResolvedUnit(path),
  fileChanges: myFsWatcher.events.map(...),
);

// Create indexer with adapter
final indexer = await IncrementalScipIndexer.openWithAdapter(
  adapter,
  packageConfig: packageConfig,
  pubspec: pubspec,
);
```

This avoids creating a second analyzer instance and shares the resolution work.

## Multi-Language Support

Adding a new language requires implementing `LanguageBinding`:

```dart
class TypeScriptBinding implements LanguageBinding {
  @override
  String get languageId => 'typescript';
  
  @override
  List<String> get extensions => ['.ts', '.tsx'];
  
  @override
  String get packageFile => 'package.json';
  
  @override
  Future<List<DiscoveredPackage>> discoverPackages(String rootPath) async {
    // Find package.json files
  }
  
  @override
  Future<PackageIndexer> createIndexer(String packagePath, {bool useCache = true}) async {
    // Create SCIP indexer for TypeScript
  }
  
  // ... other methods
}
```

Then register it:

```dart
CodeContext.registerBinding(TypeScriptBinding());
final ctx = await CodeContext.open('/path/to/ts/project');
```

## Performance

| Metric | Value |
|--------|-------|
| Initial indexing | ~10-15s for 85 files |
| Cached startup | ~300ms (35x faster) |
| Incremental update | ~100-200ms per file |
| SQL query execution | <10ms |
| Cache size | ~2.5MB for 85 files |
| SDK indexing | ~30s (one-time, cached globally) |

## Design Goals

1. **Lightweight**: Minimal dependencies, fast startup
2. **Incremental**: Only re-index changed files
3. **SQL-Native**: Standard SQL for powerful, flexible queries
4. **Extensible**: Language-agnostic core with pluggable bindings
5. **SCIP-Compatible**: Uses standard SCIP format for interoperability
6. **Bring Your Own Analyzer**: Integrate with existing IDE analyzers
