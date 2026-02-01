# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-02-XX

### Changed

#### SQL-Only Architecture
- **Replaced custom DSL with SQL queries** - All code queries now use standard SQL against an SQLite database
- **New SQL schema** with three tables:
  - `symbols` - Symbol definitions (classes, methods, functions, fields, etc.)
  - `occurrences` - Where symbols are defined and referenced
  - `relationships` - Type hierarchy and call graph edges
- **MCP tools updated**:
  - `dart_query` → `dart_sql` - Execute SQL queries
  - Added `dart_schema` - Show SQL schema and example queries
- **JSON-RPC protocol updated**:
  - `query` method → `sql` method
  - Added `schema` method

#### API Changes
- `CodeContext.query()` removed, use `CodeContext.sql()` instead
- `QueryExecutor`, `QueryParser`, `QueryResult` classes removed
- `SqlIndex`, `SqlExecutor`, `ScipToSql` classes added
- CLI now accepts SQL queries instead of DSL commands

### Removed
- All DSL commands (`def`, `refs`, `find`, `grep`, `members`, `hierarchy`, `calls`, `callers`, etc.)
- `query-dsl.md` documentation (replaced with `sql-reference.md`)
- `IndexProvider` class
- `PackageRegistryProvider` class

### Added
- `SqlIndex` - SQLite database wrapper for code index
- `SqlExecutor` - Executes SQL queries with result formatting
- `ScipToSql` - Converts SCIP data to SQL tables
- `sql-reference.md` - Complete SQL schema and query documentation
- Interactive SQL REPL mode (`code_context -i`)
- `schema` subcommand to show SQL schema

---

## [0.2.0] - 2025-01-XX

### Changed

#### API Simplification
- **Unified package registry** - Merged `IndexRegistry` and `WorkspaceRegistry` into `PackageRegistry`
- **Simplified package discovery** - Replaced `detectWorkspace()` with `discoverPackages()` that recursively finds all `pubspec.yaml` files
- **Removed deprecated APIs**:
  - `IndexRegistry` typedef (use `PackageRegistry`)
  - `WorkspaceInfo`, `WorkspaceType`, `MelosConfig` classes
  - `detectWorkspace()`, `detectWorkspaceSync()` functions
  - `fromProjectIndex()`, `withIndexes()` factory constructors
  - `unloadAll()` method

#### Testing API
- Added `PackageRegistry.forTesting()` factory for unit tests
- Added `LocalPackageIndex.forTesting()` constructor for tests without real indexer

### Fixed
- Fixed duplicate search results in `find` queries for mono repos
- Fixed `refs` queries returning 0 results due to symbol kind comparison bug
- Made mono repo indexing resilient to packages missing `package_config.json`

### Improved
- Applied 48 lint fixes (trailing commas, conditional assignments)
- Synced version between `pubspec.yaml` and `version.dart`

---

## [0.1.0] - 2025-01-XX

### Added

#### Core Features
- **Incremental SCIP indexing** with file watching and hash-based change detection
- **Index caching** for ~35x faster startup times (300ms vs 10s)
- **Query DSL** for semantic code navigation
- **Signature extraction** using the Dart analyzer for accurate signatures
- **Cross-package queries** via pre-indexed SDK/packages with PackageRegistry

#### Query Commands
- `def <symbol>` - Find symbol definitions
- `refs <symbol>` - Find all references to a symbol
- `sig <symbol>` - Get signature (declaration without body)
- `members <symbol>` - Get class/mixin/extension members
- `impls <symbol>` - Find implementations of a class/interface
- `supertypes <symbol>` - Get supertypes of a class
- `subtypes <symbol>` - Get subtypes/implementations
- `hierarchy <symbol>` - Full type hierarchy (super + sub)
- `source <symbol>` - Get source code for a symbol
- `find <pattern>` - Search symbols by pattern
- `which <symbol>` - Disambiguate multiple matches
- `grep <pattern>` - Search in source code (full grep feature parity)
- `calls <symbol>` - What does this symbol call?
- `callers <symbol>` - What calls this symbol?
- `imports <file>` - File import analysis
- `exports <path>` - File/directory export analysis
- `deps <symbol>` - Symbol dependencies
- `files` - List indexed files
- `stats` - Index statistics

#### Pattern Matching
- Glob patterns with OR: `Auth*`, `*Service`, `Scip*|*Index`
- Regex patterns: `/TODO|FIXME/`, `/error/i`
- Fuzzy matching: `~authentcate` (typo-tolerant)
- Qualified names: `MyClass.method`

#### Grep Flags (Full grep/ripgrep parity)
- `-i` - Case insensitive
- `-v` - Invert match (non-matching lines)
- `-w` - Word boundary (whole words only)
- `-l` - List files with matches
- `-L` - List files without matches
- `-c` - Count matches per file
- `-o` - Show only matched text
- `-F` - Fixed strings (literal, no regex)
- `-M` - Multiline matching
- `-D` - Search external dependencies (with `--with-deps`)
- `-C:n`, `-A:n`, `-B:n` - Context lines
- `-m:n` - Max matches per file
- `--include:glob`, `--exclude:glob` - File filtering

#### Pipe Queries
- Chain queries: `find Auth* | refs`
- Multi-stage: `find Auth* kind:class | members | source`
- Direct symbol passing (preserves full symbol identity)

#### Integrations
- CLI tool with interactive mode (`-i`) and watch mode (`-w`)
- MCP server support via `DartContextSupport` mixin
- External analyzer adapter for embedding in existing analysis infrastructure

#### CLI Subcommands
- `index-flutter [path]` - Pre-index Flutter SDK packages (flutter, flutter_test, etc.)
- `index-sdk <path>` - Pre-index the Dart SDK for cross-package queries
- `index-deps` - Pre-index all pub dependencies from pubspec.lock
- `list-indexes` - List available pre-computed SDK/package indexes
- `--with-deps` flag - Enable cross-package queries using pre-indexed dependencies

#### MCP Tools
- `dart_query` - Query codebase with DSL
- `dart_index_flutter` - Index Flutter SDK packages
- `dart_index_deps` - Index pub dependencies from pubspec.lock
- `dart_refresh` - Refresh project index and reload dependencies
- `dart_status` - Show index status (files, symbols, loaded packages, workspace info)
- `bin/mcp_server.dart` - Ready-to-use MCP server for Cursor integration

#### Mono Repo Support
- **Package discovery** - Recursively finds all `pubspec.yaml` files in any directory
- **Cross-package queries** - Query symbols across local packages
- **Unified file watching** - Single watcher at root for all packages
- **Package registry** - Central location for local and external package indexes

#### CLI Commands
- `list-packages [path]` - List discovered packages in a directory

#### Cache Infrastructure
- `CachePaths` - Centralized cache path management
- Global cache at `~/.dart_context/` mirrors pub-cache structure
- Support for hosted, git, and path dependencies
- `package_config.json` parsing for accurate dependency resolution

### Performance
- Initial indexing: ~10-15s for 85 files
- Cached startup: ~300ms
- Incremental updates: ~100-200ms per file
- Query execution: <10ms
- Cache size: ~2.5MB for 85 files

---

## [Unreleased]

### Planned
- Documentation extraction (`doc <symbol>`)
- Dead code detection (`unused`)
- Interactive REPL with result references
- Code metrics and complexity analysis

