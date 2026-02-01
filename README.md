# code_context

Language-agnostic semantic code intelligence. Query your codebase with SQL.

## Features

- **Multi-language support**: Extensible architecture with Dart as the first supported language
- **Index caching**: Persistent cache for instant startup (~300ms vs ~10s)
- **Incremental indexing**: Watches files and updates the index automatically
- **SQL queries**: Standard SQL for powerful, flexible code queries
- **Fast lookups**: O(1) symbol lookups via in-memory indexes
- **SCIP-compatible**: Uses [scip-dart](https://github.com/Workiva/scip-dart) for standard code intelligence format

## Quick Start

### Installation

```bash
# As a library
dart pub add code_context

# As a CLI tool
dart pub global activate code_context
```

### Library Usage

```dart
import 'package:code_context/code_context.dart';
import 'package:dart_binding/dart_binding.dart';

void main() async {
  // Auto-detect language from project files
  CodeContext.registerBinding(DartBinding());
  final context = await CodeContext.open('/path/to/project');

  // Query with SQL
  final classes = context.sql("SELECT name, file FROM symbols WHERE kind = 'class'");
  print(classes.toText());

  // Find references
  final refs = context.sql('''
    SELECT o.file, o.line 
    FROM occurrences o 
    JOIN symbols s ON o.symbol_id = s.scip_id 
    WHERE s.name = 'login' AND o.is_definition = 0
  ''');
  print(refs.toText());

  // Load external dependencies (SDK, packages)
  if (!context.hasDependencies) {
    await context.loadDependencies();
  }

  // Query across dependencies
  final sdkResult = context.sql("SELECT * FROM symbols WHERE name = 'String' AND kind = 'class'");
  print(sdkResult.toText());

  await context.dispose();
}
```

### CLI Usage

```bash
# Find all classes
code_context "SELECT name, file FROM symbols WHERE kind = 'class'"

# Pattern matching
code_context "SELECT name, file FROM symbols WHERE name GLOB 'Auth*'"

# Interactive SQL REPL mode
code_context -i

# Show schema
code_context schema

# Dart-specific commands (namespaced with dart:)
code_context dart:index-sdk /path/to/sdk
code_context dart:index-flutter
code_context dart:index-deps
code_context dart:list-indexes
```

## SQL Schema

| Table | Description |
|-------|-------------|
| `symbols` | Symbol definitions (classes, methods, fields, etc.) |
| `occurrences` | Where symbols are defined and referenced |
| `relationships` | Type hierarchy and call graph edges |

### Common Queries

| Task | SQL |
|------|-----|
| Find all classes | `SELECT * FROM symbols WHERE kind = 'class'` |
| Find symbol | `SELECT * FROM symbols WHERE name = 'MyClass'` |
| Find references | `SELECT o.* FROM occurrences o JOIN symbols s ON o.symbol_id = s.scip_id WHERE s.name = 'foo' AND o.is_definition = 0` |
| Class members | `SELECT * FROM symbols WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass')` |
| Pattern match | `SELECT * FROM symbols WHERE name GLOB '*Service*'` |
| Find callers | `SELECT s.name FROM relationships r JOIN symbols s ON r.from_symbol = s.scip_id WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'foo') AND r.kind = 'calls'` |

[Full SQL Reference →](doc/sql-reference.md)

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](doc/getting-started.md) | Installation and basic usage |
| [SQL Reference](doc/sql-reference.md) | Complete schema and query reference |
| [Architecture](doc/architecture.md) | How it works, package structure |
| [SCIP Server](doc/scip-server.md) | JSON-RPC protocol server |
| [MCP Integration](doc/mcp-integration.md) | Using with Cursor/AI agents |
| [Monorepo Support](doc/monorepo.md) | Multi-package workspaces |
| [Cross-Package Queries](doc/cross-package-queries.md) | Querying SDK and dependencies |
| [Analyzer Integration](doc/analyzer-integration.md) | Sharing analyzer contexts |

## Performance

| Metric | Value |
|--------|-------|
| Initial indexing | ~10-15s for 85 files |
| Cached startup | ~300ms (35x faster) |
| Incremental update | ~100-200ms per file |
| SQL query execution | <10ms |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CodeContext                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────┐│
│  │ LLM / Agent  │────▶│  SQL Query   │────▶│      SqlExecutor         ││
│  └──────────────┘     └──────────────┘     └────────────┬─────────────┘│
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
│  │ + Indexer (live)  │  │ (in-memory)   │  │ SDK/Flutter/pub        │ │
│  └───────────────────┘  └───────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

[Full Architecture →](doc/architecture.md)

## Package Structure

This project is organized as a Dart pub workspace:

```
code_context/
├── packages/
│   ├── scip_server/      # Language-agnostic SCIP protocol core
│   └── dart_binding/     # Dart-specific implementation
├── lib/                  # Root package (re-exports)
├── bin/                  # CLI and MCP server
└── doc/                  # Documentation
```

## Supported Languages

| Language | Status | Binding |
|----------|--------|---------|
| Dart | ✅ Full support | `DartBinding` |
| TypeScript | 🔜 Planned | - |
| Python | 🔜 Planned | - |

## Related Projects

- [scip-dart](https://github.com/Workiva/scip-dart) - SCIP indexer for Dart
- [SCIP](https://github.com/sourcegraph/scip) - Code Intelligence Protocol

## License

MIT
