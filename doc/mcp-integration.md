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
- "Use dart_sql to find all classes in the project"

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `dart_sql` | Execute SQL queries against the code index |
| `dart_schema` | Show SQL schema and example queries |
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

The mixin automatically:
- Registers `DartBinding()` for Dart project auto-detection
- Indexes project roots on first query
- Caches indexes for fast subsequent queries  
- Watches for file changes and updates incrementally
- Loads pre-computed SDK/package indexes
- Watches package_config.json and notifies when deps change

## Tool Details

### dart_sql

Execute SQL queries against the code index:

```
dart_sql(sql: "SELECT name, file FROM symbols WHERE kind = 'class'")
dart_sql(sql: "SELECT * FROM symbols WHERE name GLOB 'Auth*'")
dart_sql(sql: "SELECT o.file, o.line FROM occurrences o JOIN symbols s ON o.symbol_id = s.scip_id WHERE s.name = 'login'")
```

Returns formatted text (Markdown table) or JSON depending on format parameter.

### dart_schema

Shows the SQL schema and example queries:

```
dart_schema()
```

Returns schema documentation with column descriptions and common query patterns.

### dart_status

Shows current index state:

```json
{
  "files": 85,
  "symbols": 1234,
  "occurrences": 5678,
  "relationships": 890,
  "packages": ["my_app", "my_core"],
  "externalLoaded": ["flutter-3.32.0", "collection-1.18.0"],
  "sdkLoaded": "3.7.1"
}
```

### dart_index_flutter

Pre-indexes Flutter SDK for cross-package queries. Run once per Flutter version:

```
dart_index_flutter(flutterRoot: "/path/to/flutter")
```

Takes ~1-2 minutes. Enables queries across your project and Flutter SDK.

### dart_index_deps

Indexes all dependencies from pubspec.lock:

```
dart_index_deps(projectRoot: "/path/to/project")
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

## Example SQL Queries for Agents

```sql
-- Find all classes
SELECT name, file, line FROM symbols WHERE kind = 'class';

-- Find a symbol definition
SELECT s.name, o.file, o.line 
FROM symbols s 
JOIN occurrences o ON s.scip_id = o.symbol_id 
WHERE s.name = 'AuthService' AND o.is_definition = 1;

-- Find references
SELECT o.file, o.line 
FROM occurrences o 
JOIN symbols s ON o.symbol_id = s.scip_id 
WHERE s.name = 'login' AND o.is_definition = 0;

-- Get class members
SELECT name, kind FROM symbols 
WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'AuthService' LIMIT 1);

-- Find callers
SELECT s.name, s.file 
FROM relationships r 
JOIN symbols s ON r.from_symbol = s.scip_id 
WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'validateUser')
  AND r.kind = 'calls';

-- Pattern matching
SELECT name, file FROM symbols WHERE name GLOB '*Service*' AND kind = 'class';
```

## Multi-Language Support

The MCP server uses auto-detection to select the appropriate language binding:

1. On initialization, bindings are registered (currently `DartBinding`)
2. When a project root is set, `CodeContext.open()` auto-detects the language
3. The correct binding is used based on project files (`pubspec.yaml` -> Dart)

Future language bindings (TypeScript, Python) will work the same way - just register them at startup and auto-detection handles the rest.
