/// Language-agnostic SCIP query engine with SQL interface.
///
/// This library provides:
/// - [ScipIndex] - In-memory representation of a SCIP index
/// - [SqlIndex] - SQLite database for SQL queries
/// - [ScipToSql] - Convert SCIP data to SQL
/// - [SqlExecutor] - Execute SQL queries with formatting
/// - [LanguageBinding] - Interface for language-specific implementations
/// - [ScipServer] - JSON-RPC protocol server
library scip_server;

// Core index types
export 'src/index/scip_index.dart';

// SQL database
export 'src/sql/sql_index.dart';
export 'src/sql/scip_to_sql.dart';
export 'src/sql/sql_executor.dart';

// Language binding interface
export 'src/language_binding.dart';

// Protocol server
export 'src/protocol/protocol.dart';
export 'src/protocol/json_rpc_server.dart';
