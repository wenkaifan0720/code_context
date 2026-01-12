# code_context

Lightweight semantic code intelligence. Query your codebase with a simple DSL.

> Currently supports Dart with a pluggable architecture for adding other languages.

## Features

- **Index caching**: Persistent cache for instant startup (~300ms vs ~10s)
- **Incremental indexing**: Watches files and updates the index automatically
- **Simple query DSL**: Human and LLM-friendly query language
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

void main() async {
  final context = await CodeContext.open('/path/to/project');

  // Query with DSL
  final result = await context.query('def AuthRepository');
  print(result.toText());

  // Find references
  final refs = await context.query('refs login');
  print(refs.toText());

  await context.dispose();
}
```

### CLI Usage

```bash
# Find definition
code_context def AuthRepository

# Find references  
code_context refs login

# Search with filters
code_context "find Auth* kind:class"

# Interactive mode
code_context -i
```

## Query DSL

| Query | Description | Example |
|-------|-------------|---------|
| `def <symbol>` | Find definition | `def AuthRepository` |
| `refs <symbol>` | Find references | `refs login` |
| `find <pattern>` | Search symbols | `find Auth*` |
| `grep <pattern>` | Search source | `grep /TODO\|FIXME/` |
| `members <symbol>` | Class members | `members MyClass` |
| `hierarchy <symbol>` | Type hierarchy | `hierarchy MyWidget` |
| `calls <symbol>` | What it calls | `calls login` |
| `callers <symbol>` | What calls it | `callers validateUser` |

[Full DSL Reference →](doc/query-dsl.md)

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](doc/getting-started.md) | Installation and basic usage |
| [Query DSL](doc/query-dsl.md) | Complete command reference |
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
| Query execution | <10ms |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CodeContext                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────┐│
│  │ LLM / Agent  │────▶│ Query String │────▶│    QueryExecutor         ││
│  └──────────────┘     └──────────────┘     └────────────┬─────────────┘│
│                                                         ▼              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     PackageRegistry                              │  │
│  │  Local packages (mutable) + External packages (cached)          │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│              ┌───────────────────┼───────────────────┐                 │
│              ▼                   ▼                   ▼                 │
│  ┌───────────────────┐  ┌───────────────┐  ┌────────────────────────┐ │
│  │ LocalPackageIndex │  │ ScipIndex     │  │ ExternalPackageIndex   │ │
│  │ + Indexer (live)  │  │ O(1) lookups  │  │ SDK/Flutter/pub        │ │
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

## Related Projects

- [scip-dart](https://github.com/Workiva/scip-dart) - SCIP indexer for Dart
- [SCIP](https://github.com/sourcegraph/scip) - Code Intelligence Protocol

## License

MIT
