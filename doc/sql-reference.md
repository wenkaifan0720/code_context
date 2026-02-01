# SQL Query Reference

code_context uses SQL for querying code intelligence data. The index is stored in an SQLite database with three main tables.

## Schema

### symbols

Symbol definitions (classes, methods, functions, fields, etc.)

| Column | Type | Description |
|--------|------|-------------|
| scip_id | TEXT PRIMARY KEY | SCIP symbol identifier |
| name | TEXT | Symbol name |
| kind | TEXT | class, method, function, field, enum, etc. |
| file | TEXT | Relative file path (NULL for external) |
| line | INTEGER | Definition line (0-indexed) |
| column_num | INTEGER | Definition column |
| package | TEXT | Package name |
| version | TEXT | Package version |
| container_id | TEXT | Parent symbol SCIP ID |
| display_name | TEXT | Human-readable name |
| documentation | TEXT | Doc comments |
| language | TEXT | Language identifier |

### occurrences

Where symbols are defined and referenced.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PRIMARY KEY | Auto-increment ID |
| symbol_id | TEXT | References symbols.scip_id |
| file | TEXT | File path |
| line | INTEGER | Line number (0-indexed) |
| column_num | INTEGER | Column number |
| end_line | INTEGER | End line |
| end_column | INTEGER | End column |
| is_definition | INTEGER | 1 if definition, 0 if reference |
| enclosing_end_line | INTEGER | End of enclosing scope |

### relationships

Type hierarchy and call graph edges.

| Column | Type | Description |
|--------|------|-------------|
| from_symbol | TEXT | Source symbol |
| to_symbol | TEXT | Target symbol |
| kind | TEXT | implements, calls, type_definition, references |

## Symbol Kinds

`class`, `method`, `function`, `field`, `enum`, `mixin`, `extension`, `getter`, `setter`, `constructor`, `parameter`, `variable`

## Common Queries

### Find all classes

```sql
SELECT name, file, line FROM symbols WHERE kind = 'class';
```

### Find symbol definition

```sql
SELECT s.name, o.file, o.line 
FROM symbols s 
JOIN occurrences o ON s.scip_id = o.symbol_id 
WHERE s.name = 'MyClass' AND o.is_definition = 1;
```

### Find all references to a symbol

```sql
SELECT o.file, o.line, o.column_num 
FROM occurrences o 
JOIN symbols s ON o.symbol_id = s.scip_id 
WHERE s.name = 'login' AND o.is_definition = 0;
```

### Get class members

```sql
SELECT name, kind, line 
FROM symbols 
WHERE container_id = (SELECT scip_id FROM symbols WHERE name = 'MyClass' LIMIT 1);
```

### Find callers of a function

```sql
SELECT s.name, s.file, s.line 
FROM relationships r 
JOIN symbols s ON r.from_symbol = s.scip_id 
WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'login')
  AND r.kind = 'calls';
```

### Find what a function calls

```sql
SELECT s.name, s.kind 
FROM relationships r 
JOIN symbols s ON r.to_symbol = s.scip_id 
WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'handleSubmit')
  AND r.kind = 'calls';
```

### Find type hierarchy (implements)

```sql
-- Find what a class implements
SELECT s.name 
FROM relationships r 
JOIN symbols s ON r.to_symbol = s.scip_id 
WHERE r.from_symbol IN (SELECT scip_id FROM symbols WHERE name = 'MyService')
  AND r.kind = 'implements';

-- Find implementers of an interface
SELECT s.name, s.file 
FROM relationships r 
JOIN symbols s ON r.from_symbol = s.scip_id 
WHERE r.to_symbol IN (SELECT scip_id FROM symbols WHERE name = 'Repository')
  AND r.kind = 'implements';
```

### Pattern matching with GLOB

```sql
-- Find all symbols containing "Service"
SELECT name, kind, file FROM symbols WHERE name GLOB '*Service*';

-- Find all Auth-prefixed classes
SELECT name, file, line FROM symbols 
WHERE name GLOB 'Auth*' AND kind = 'class';
```

### Filter by file path

```sql
-- All methods in auth directory
SELECT name, file, line FROM symbols 
WHERE kind = 'method' AND file GLOB 'lib/auth/*';

-- All classes in a specific file
SELECT name, line FROM symbols 
WHERE kind = 'class' AND file = 'lib/main.dart';
```

### Count symbols

```sql
SELECT kind, COUNT(*) as count 
FROM symbols 
GROUP BY kind 
ORDER BY count DESC;
```

### Find files with most symbols

```sql
SELECT file, COUNT(*) as symbol_count 
FROM symbols 
WHERE file IS NOT NULL 
GROUP BY file 
ORDER BY symbol_count DESC 
LIMIT 10;
```

## CLI Usage

```bash
# Execute a SQL query
code_context "SELECT * FROM symbols WHERE kind = 'class'"

# Interactive SQL REPL
code_context -i

# In interactive mode:
sql> SELECT name, file FROM symbols WHERE kind = 'class' LIMIT 5;
sql> .schema     # Show schema
sql> .tables     # List tables
sql> .stats      # Show statistics
sql> .refresh    # Refresh index
sql> .quit       # Exit

# With external dependencies
code_context --with-deps "SELECT * FROM symbols WHERE name = 'StatelessWidget'"
```

## Output Formats

```bash
# Text format (default) - Markdown table
code_context "SELECT name, kind FROM symbols LIMIT 5"

# JSON format
code_context -f json "SELECT name, kind FROM symbols LIMIT 5"
```

## Notes

- Only SELECT queries are allowed (read-only)
- Results are limited to 1000 rows by default
- Line and column numbers are 0-indexed
- External symbols (from SDK/packages) have NULL file paths
- Use GLOB for pattern matching (SQLite syntax)
