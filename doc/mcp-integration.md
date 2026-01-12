# MCP Integration

code_context provides full MCP (Model Context Protocol) support for AI agents.

## Using with Cursor

A ready-to-use MCP server is included. Add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "code_context": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "/path/to/code_context/bin/mcp_server.dart"]
    }
  }
}
```

Restart Cursor, then ask Claude to use the tools:
- "Use dart_status to check the index"
- "Use dart_index_flutter to index the Flutter SDK"
- "Use dart_query to find references to MyClass"

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `dart_query` | Query codebase with DSL (refs, def, find, grep, etc.) |
| `dart_index_flutter` | Index Flutter SDK packages (~1 min, one-time) |
| `dart_index_deps` | Index pub dependencies from pubspec.lock |
| `dart_refresh` | Refresh project index and reload dependencies |
| `dart_status` | Show index status (files, symbols, packages loaded) |

## Custom MCP Server

Add `CodeContextSupport` to your own MCP server:

```dart
import 'package:code_context/code_context_mcp.dart';
import 'package:dart_mcp/server.dart';

base class MyServer extends MCPServer 
    with LoggingSupport, ToolsSupport, RootsTrackingSupport, CodeContextSupport {
  // Your server implementation
}
```

The tools automatically:
- Index project roots on first query
- Cache indexes for fast subsequent queries  
- Watch for file changes and update incrementally
- Load pre-computed SDK/package indexes
- Watch package_config.json and notify when deps change

## Tool Details

### dart_query

Execute any DSL query:

```
dart_query("refs AuthService.login")
dart_query("find Auth* kind:class")
dart_query("grep TODO -l")
```

Returns formatted text or JSON depending on query type.

### dart_status

Shows current index state:

```json
{
  "files": 85,
  "symbols": 1234,
  "references": 5678,
  "packages": ["my_app", "my_core"],
  "externalLoaded": ["flutter-3.32.0", "collection-1.18.0"]
}
```

### dart_index_flutter

Pre-indexes Flutter SDK for cross-package queries. Run once per Flutter version:

```
dart_index_flutter("/path/to/flutter")
```

Takes ~1-2 minutes. Enables queries like `hierarchy MyWidget` showing Flutter types.

### dart_index_deps

Indexes all dependencies from pubspec.lock:

```
dart_index_deps("/path/to/project")
```

Run after adding new dependencies or setting up a new project.

### dart_refresh

Force refresh the index:

```
dart_refresh()                    # Normal refresh
dart_refresh(fullReindex: true)   # Full re-index from scratch
```

Use when:
- pubspec.yaml or pubspec.lock changes
- Major refactoring
- Index seems stale

