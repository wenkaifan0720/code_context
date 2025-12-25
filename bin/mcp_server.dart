// Copyright (c) 2025. Dart code intelligence MCP server.
/// 
/// This server provides semantic code intelligence for Dart via MCP.
/// 
/// ## Usage with Cursor
/// 
/// Add to ~/.cursor/mcp.json:
/// ```json
/// {
///   "mcpServers": {
///     "dart_context": {
///       "command": "dart",
///       "args": ["run", "/path/to/dart_context/bin/mcp_server.dart"]
///     }
///   }
/// }
/// ```
/// 
/// ## Available Tools
/// 
/// - `dart_query` - Query Dart codebase with DSL
/// - `dart_index_flutter` - Index Flutter SDK packages
/// - `dart_index_deps` - Index pub dependencies
/// - `dart_refresh` - Refresh project index
/// - `dart_status` - Show index status
library;

import 'dart:io' as io;

import 'package:dart_mcp/server.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:dart_context/dart_context_mcp.dart';

void main() {
  // Create the server and connect it to stdio.
  DartContextServer(stdioChannel(input: io.stdin, output: io.stdout));
}

/// MCP server with Dart code intelligence support.
base class DartContextServer extends MCPServer
    with LoggingSupport, ToolsSupport, RootsTrackingSupport, DartContextSupport {
  DartContextServer(super.channel)
      : super.fromStreamChannel(
          implementation: Implementation(
            name: 'dart_context',
            version: '1.0.0',
          ),
          instructions: '''Dart code intelligence server.

Use dart_status to check index status.
Use dart_index_flutter to index Flutter SDK (one-time setup).
Use dart_index_deps to index project dependencies.
Use dart_query to query the codebase with DSL.

Example queries:
- "def AuthRepository" - Find definition
- "refs login" - Find references  
- "hierarchy MyWidget" - Type hierarchy
- "grep /TODO|FIXME/ -l" - Search source code
''',
        );
}

