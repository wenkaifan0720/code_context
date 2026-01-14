# Getting Started

## Installation

### As a Library

```bash
dart pub add dart_context
```

### As a CLI Tool

```bash
dart pub global activate dart_context
```

## Quick Start

### Library Usage

```dart
import 'package:dart_context/dart_context.dart';

void main() async {
  // Open a project
  final context = await DartContext.open('/path/to/project');

  // Query with DSL
  final result = await context.query('def AuthRepository');
  print(result.toText());

  // Find references
  final refs = await context.query('refs login');
  print(refs.toText());

  // Get class members
  final members = await context.query('members MyClass');
  print(members.toJson());

  // Watch for updates
  context.updates.listen((update) {
    print('Index updated: $update');
  });

  // Cleanup
  await context.dispose();
}
```

### CLI Usage

```bash
# Find definition
dart_context def AuthRepository

# Find references
dart_context refs login

# Get class members
dart_context members MyClass

# Search with filters
dart_context "find Auth* kind:class"
dart_context "find * kind:method in:lib/auth/"

# Interactive mode
dart_context -i

# Watch mode (shows file changes)
dart_context -w

# Watch mode with auto-rerun query
dart_context -w "find * kind:class"

# JSON output
dart_context -f json refs login

# Force full re-index (skip cache)
dart_context --no-cache stats
```

## Next Steps

- [Query DSL Reference](query-dsl.md) - Full command reference
- [Architecture](architecture.md) - How it works
- [MCP Integration](mcp-integration.md) - Using with Cursor/AI agents
- [Monorepo Support](monorepo.md) - Multi-package workspaces

