# Getting Started

## Installation

### As a Library

```bash
dart pub add code_context
dart pub add dart_binding  # For Dart projects
```

### As a CLI Tool

```bash
dart pub global activate code_context
```

## Quick Start

### Library Usage

```dart
import 'package:code_context/code_context.dart';
import 'package:dart_binding/dart_binding.dart';

void main() async {
  // Register available language bindings
  CodeContext.registerBinding(DartBinding());

  // Open a project (auto-detects language)
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

  // Get class members
  final members = context.sql('''
    SELECT name, kind FROM symbols 
    WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass' LIMIT 1)
  ''');
  print(members.toJson());

  // Load external dependencies (SDK, packages)
  if (!context.hasDependencies) {
    await context.loadDependencies();
  }

  // Query across dependencies
  final sdkResult = context.sql("SELECT name FROM symbols WHERE name = 'String' AND kind = 'class'");
  print(sdkResult.toText());

  // Cleanup
  await context.dispose();
}
```

### CLI Usage

```bash
# Find all classes
code_context "SELECT name, file FROM symbols WHERE kind = 'class'"

# Find symbol definition
code_context "SELECT s.name, o.file, o.line FROM symbols s JOIN occurrences o ON s.scip_id = o.symbol_id WHERE s.name = 'AuthRepository' AND o.is_definition = 1"

# Pattern matching
code_context "SELECT name, file FROM symbols WHERE name GLOB 'Auth*' AND kind = 'class'"
code_context "SELECT name, file FROM symbols WHERE kind = 'method' AND file GLOB 'lib/auth/*'"

# With external dependencies
code_context --with-deps "SELECT * FROM symbols WHERE name = 'BuildContext'"

# Interactive SQL REPL mode
code_context -i

# Watch mode (shows file changes)
code_context -w

# JSON output
code_context -f json "SELECT name, kind FROM symbols LIMIT 5"

# Show schema
code_context schema

# Force full re-index (skip cache)
code_context --no-cache "SELECT COUNT(*) FROM symbols"

# Dart-specific commands
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

## Common Queries

| Task | SQL |
|------|-----|
| Find all classes | `SELECT * FROM symbols WHERE kind = 'class'` |
| Find symbol definition | `SELECT * FROM symbols WHERE name = 'MyClass'` |
| Find references | `SELECT o.* FROM occurrences o JOIN symbols s ON o.symbol_id = s.scip_id WHERE s.name = 'foo' AND o.is_definition = 0` |
| Get class members | `SELECT * FROM symbols WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass')` |
| Pattern match | `SELECT * FROM symbols WHERE name GLOB '*Service*'` |
| Filter by path | `SELECT * FROM symbols WHERE file GLOB 'lib/auth/*'` |

## Next Steps

- [SQL Reference](sql-reference.md) - Full schema and query examples
- [Architecture](architecture.md) - How it works
- [MCP Integration](mcp-integration.md) - Using with Cursor/AI agents
- [Monorepo Support](monorepo.md) - Multi-package workspaces
- [Cross-Package Queries](cross-package-queries.md) - Querying SDK and dependencies
- [Analyzer Integration](analyzer-integration.md) - Sharing analyzer contexts
