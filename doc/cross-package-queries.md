# Cross-Package Queries

code_context supports querying across external dependencies (SDK, Flutter, pub packages) by pre-computing their indexes.

## Pre-Indexing Commands

```bash
# Pre-index the Dart SDK (do this once per SDK version)
code_context dart:index-sdk /path/to/dart-sdk

# Pre-index Flutter SDK packages (do this once per Flutter version)
code_context dart:index-flutter /path/to/flutter

# Pre-index all dependencies from pubspec.lock
code_context dart:index-deps

# List available pre-computed indexes
code_context dart:list-indexes
```

## Using Pre-Computed Indexes

```bash
# Query with dependencies loaded
code_context --with-deps "SELECT * FROM symbols WHERE name = 'StatelessWidget'"

# Find Flutter widget hierarchy
code_context --with-deps "SELECT s.name FROM relationships r JOIN symbols s ON r.to_symbol = s.scip_id WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'MyWidget') AND r.kind = 'implements'"

# Search in SDK types
code_context --with-deps "SELECT name, kind FROM symbols WHERE name GLOB 'List*' AND kind = 'class'"
```

## Global Cache Structure

Indexes are stored in `~/.dart_context/` with a structure that mirrors pub cache:

```
~/.dart_context/                      # Global cache
├── sdk/
│   └── 3.7.1/index.scip              # Dart SDK (versioned)
├── flutter/
│   └── 3.32.0/flutter/index.scip     # Flutter SDK packages
├── hosted/
│   ├── collection-1.18.0/index.scip  # Pub packages
│   └── analyzer-6.3.0/index.scip
└── git/
    └── fluxon-bfef6c5e/index.scip    # Git dependencies
```

## Example Queries

With pre-computed indexes, you can:

```bash
# Find type hierarchy
code_context --with-deps "SELECT s.name FROM relationships r JOIN symbols s ON r.to_symbol = s.scip_id WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'SignatureVisitor') AND r.kind = 'implements'"
# Output: Shows that it extends RecursiveAstVisitor from analyzer

# Find all implementers of an interface
code_context --with-deps "SELECT s.name, s.file FROM relationships r JOIN symbols s ON r.from_symbol = s.scip_id WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'StatefulWidget') AND r.kind = 'implements'"
# Output: All classes implementing StatefulWidget

# Find uses of a Flutter class
code_context --with-deps "SELECT o.file, o.line FROM occurrences o JOIN symbols s ON o.symbol_id = s.scip_id WHERE s.name = 'StatefulWidget' AND o.is_definition = 0"
# Output: All files referencing StatefulWidget

# Search SDK types with pattern
code_context --with-deps "SELECT name, kind FROM symbols WHERE name GLOB 'int*' AND kind = 'class'"
```

## Loading Dependencies Programmatically

```dart
import 'package:code_context/code_context.dart';
import 'package:dart_binding/dart_binding.dart';

CodeContext.registerBinding(DartBinding());
final context = await CodeContext.open('/path/to/project');

// Load all dependencies from pubspec.lock
final result = await context.loadDependencies();
print('Loaded ${result.loaded} packages');
print('Skipped ${result.skipped} (already cached)');
print('Failed: ${result.failed}');

// Now queries include dependencies
final hierarchy = context.sql('''
  SELECT s.name 
  FROM relationships r 
  JOIN symbols s ON r.to_symbol = s.scip_id 
  WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'MyWidget')
    AND r.kind = 'implements'
''');
print(hierarchy.toText());
```

## Performance Considerations

- Pre-indexing takes time (~30s for SDK, ~1-2 min for Flutter SDK)
- Once indexed, loading is instant (just reads from disk)
- Only index what you need (SDK vs Flutter vs all deps)
- Indexes are shared across projects (stored globally)
- SDK/Flutter indexes are versioned (no conflicts between versions)

**Note**: Pre-indexing is optional. By default, code_context only indexes your project code.
