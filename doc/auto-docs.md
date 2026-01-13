# LLM-Generated Documentation

## Overview

code_context enables automatic generation of human-readable documentation using LLMs, with SCIP-based dependency tracking for efficient incremental updates. This is similar to tools like DeepWiki or Code Wiki, but leverages our existing SCIP infrastructure for smarter change detection.

## Design Goals

1. **LLM-synthesized prose** - Not just symbol listings, but actual documentation
2. **Smart symbols** - Stable references that survive code movement
3. **Bottom-up generation** - Folder → module → project hierarchy
4. **Structure-aware updates** - Only regenerate when API/signatures change, not implementation
5. **Two-stage pipeline** - Separate expensive LLM generation from cheap link resolution

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Two-Stage Documentation Pipeline                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  STAGE 1: Generation (expensive, on structure change only)          │
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌───────────────────┐   │
│  │  SCIP Index  │────▶│  Structure   │────▶│  LLM Synthesis    │   │
│  │              │     │  Hash Check  │     │  (if hash changed)│   │
│  └──────────────┘     └──────────────┘     └─────────┬─────────┘   │
│                                                       │             │
│                                                       ▼             │
│                                            ┌───────────────────┐   │
│                                            │  Source Docs      │   │
│                                            │  (scip:// links)  │   │
│                                            └─────────┬─────────┘   │
│                                                       │             │
├───────────────────────────────────────────────────────┼─────────────┤
│                                                       │             │
│  STAGE 2: Link Resolution (cheap, on any file change)│             │
│                                                       ▼             │
│  ┌──────────────┐     ┌──────────────┐     ┌───────────────────┐   │
│  │  SCIP Index  │────▶│  Link        │────▶│  Rendered Docs    │   │
│  │  (current)   │     │  Transformer │     │  (navigable)      │   │
│  └──────────────┘     └──────────────┘     └───────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Two Stages?

| Stage | Cost | Trigger | Output |
|-------|------|---------|--------|
| Generation | Expensive (LLM) | Structure hash changes | Source docs with `scip://` links |
| Resolution | Cheap (lookup) | Any file change | Rendered docs with `file:line` links |

This separation means:
- Implementation changes (no signature change) → Only re-resolve links, no LLM call
- Line number changes → Only re-resolve links, no LLM call
- Signature/API changes → Regenerate docs AND re-resolve links

## Structure Hash (SCIP-Based)

Instead of hashing file contents, we hash the **documentation-relevant structure** from SCIP:

```dart
/// Extracts doc-relevant parts from SCIP symbols in a folder.
/// 
/// Captures:
/// - Symbol names and kinds
/// - Signatures (parameters, return types)  
/// - Doc comments
/// - Relationships (calls, implements)
///
/// Does NOT capture:
/// - Implementation bodies
/// - Line numbers
/// - Formatting/whitespace
List<String> extractDocRelevantParts(List<SymbolInformation> symbols) {
  final parts = <String>[];
  
  for (final symbol in symbols) {
    if (symbol.isLocal) continue;  // Skip local/anonymous
    
    parts.add('symbol:${symbol.symbol}:${symbol.kind}');
    
    if (symbol.signature.isNotEmpty) {
      parts.add('sig:${symbol.symbol}:${symbol.signature}');
    }
    
    if (symbol.documentation.isNotEmpty) {
      parts.add('doc:${symbol.symbol}:${symbol.documentation}');
    }
    
    for (final ref in symbol.relationships) {
      parts.add('rel:${symbol.symbol}:${ref.symbol}:${ref.kind}');
    }
  }
  
  return parts;
}

String computeFolderStructureHash(String folderPath, ScipIndex index) {
  final symbols = index.symbolsInFolder(folderPath);
  final parts = extractDocRelevantParts(symbols);
  parts.sort();  // Deterministic ordering
  return md5(parts.join('|'));
}
```

### What Triggers Doc Regeneration?

| Change Type | Structure Hash Changes? | Regen Docs? |
|-------------|------------------------|-------------|
| Rename function | ✓ symbol name changes | YES |
| Change signature | ✓ signature changes | YES |
| Update doc comment | ✓ documentation changes | YES |
| Add/remove public API | ✓ symbol added/removed | YES |
| Change function body | ✗ not in SCIP | NO |
| Change private variable value | ✗ not in SCIP | NO |
| Reformat code | ✗ not in SCIP | NO |
| Move code (line numbers) | ✗ not hashed | NO |

## Smart Symbols

Generated docs contain **smart symbols** - stable references to code elements:

```markdown
The [`AuthService`][auth-service] handles user authentication by delegating
to the [`AuthRepository`][auth-repo] for data persistence.

[auth-service]: scip://lib/services/auth_service.dart/AuthService#
[auth-repo]: scip://lib/repositories/auth_repository.dart/AuthRepository#
```

### Why scip:// URIs?

The `scip://` URI is a **stable identifier** based on symbol name/path, not line numbers:

```
scip://<relative-path>/<SymbolName>#[member]

Examples:
- scip://lib/auth/service.dart/AuthService#
- scip://lib/auth/service.dart/AuthService#login().
- scip://lib/auth/service.dart/AuthService#authState.
```

Benefits:
- **Survives code movement**: Line numbers change, but URI stays stable
- **Queryable**: Agents can resolve to current location via SCIP
- **Cheap updates**: Only re-resolve on file change, no doc regeneration needed

### Link Resolution (Stage 2)

Transform `scip://` URIs to navigable links:

```dart
String transformDoc(
  String sourceDoc, 
  ScipIndex index, 
  {LinkStyle style = LinkStyle.relative}
) {
  final pattern = RegExp(r'\[([^\]]+)\]:\s*scip://([^\s]+)');
  
  return sourceDoc.replaceAllMapped(pattern, (match) {
    final label = match.group(1)!;
    final scipUri = match.group(2)!;
    
    final location = index.resolve(scipUri);
    if (location == null) {
      return '[$label]: #symbol-not-found';
    }
    
    final link = switch (style) {
      LinkStyle.relative => '${location.relativePath}#L${location.line}',
      LinkStyle.github => 'https://github.com/repo/blob/main/${location.path}#L${location.line}',
      LinkStyle.absolute => 'file://${location.absolutePath}',
    };
    
    return '[$label]: $link';
  });
}
```

### Source vs Rendered Docs

**Source doc** (stored, stable):
```markdown
[login]: scip://lib/features/auth/auth_service.dart/AuthService#login().
```

**Rendered doc** (generated, navigable):
```markdown
[login]: ../../lib/features/auth/auth_service.dart#L42
```

For external packages:
```markdown
# Source (stable)
[signIn]: scip://firebase_auth@4.6.0/lib/src/firebase_auth.dart/FirebaseAuth#signInWithEmailAndPassword().

# Rendered (pub cache path)
[signIn]: ~/.pub-cache/hosted/pub.dev/firebase_auth-4.6.0/lib/src/firebase_auth.dart#L142

# Rendered (GitHub)
[signIn]: https://github.com/firebase/flutterfire/blob/.../firebase_auth.dart#L142
```

## Cache Structure

```
/path/to/package/.dart_context/
├── index.scip                    # SCIP index
├── manifest.json                 # Index manifest
└── docs/
    ├── manifest.json             # Doc manifest (structure hashes, deps)
    ├── source/                   # LLM-generated (expensive, stable)
    │   ├── index.md              # Project-level
    │   ├── modules/
    │   │   └── auth.md
    │   └── folders/
    │       └── lib/features/auth/
    │           └── README.md
    │
    └── rendered/                 # Transformed (cheap, always fresh)
        ├── index.md              # With resolved file:line links
        ├── modules/
        │   └── auth.md
        └── folders/
            └── lib/features/auth/
                └── README.md
```

### External Package Docs

```
~/.dart_context/
├── hosted/http-1.2.0/
│   ├── index.scip
│   └── docs/
│       └── source/
│           └── index.md          # Package overview (from existing README)
└── flutter/3.32.0/material/
    ├── index.scip
    └── docs/
        └── source/
            └── index.md
```

## Folder Dependency Graph

Dependencies are tracked at **folder level**, aggregated from file imports:

```
lib/features/auth/
    ├── imports from (internal folders):
    │   ├── lib/core/           ← include this folder's doc
    │   └── lib/data/           ← include this folder's doc
    │
    ├── imports from (external packages):
    │   ├── firebase_auth       ← include package docs
    │   └── shared_preferences  ← include package docs
    │
    └── imported by (dependents):
        └── lib/ui/auth/        ← mention what's used
```

### Building the Folder Graph

```dart
/// Build folder-level dependency graph from file imports.
Map<String, Set<String>> buildFolderDependencies(ScipIndex index) {
  final graph = <String, Set<String>>{};
  
  for (final file in index.files) {
    final folder = dirname(file.path);
    graph.putIfAbsent(folder, () => {});
    
    for (final import in file.imports) {
      final depFolder = dirname(import.path);
      if (depFolder != folder) {  // Skip same-folder imports
        graph[folder]!.add(depFolder);
      }
    }
  }
  
  return graph;
}
```

### Circular Dependency Handling

Use Tarjan's SCC algorithm:

```
1. Build folder dependency graph from imports
2. Find SCCs (Strongly Connected Components) - folders that form cycles
3. Topological sort of SCCs

For cycles (A ↔ B):
  Generate both folders in same LLM session with mutual context.
  Agent sees both folders' code before generating either doc.
```

## LLM Context Building

### Context for Folder Doc

```yaml
# Context sent to LLM for: lib/features/auth/

metadata:
  path: lib/features/auth/
  purpose_hint: "auth feature (from path)"

# FULL CONTEXT: Current folder
files:
  - name: auth_service.dart
    doc_comments: |
      /// Handles user authentication and session management.
    public_api:
      - "class AuthService"
      - "  Future<User> login(String email, String password)"
      - "  Future<void> logout()"

symbols:
  definitions:
    - id: "scip://lib/features/auth/auth_service.dart/AuthService#"
      name: AuthService
      kind: class
  relationships:
    - AuthService calls AuthRepository.signIn
    - AuthService calls TokenManager.store

# SUMMARY CONTEXT: Internal folder dependencies
internal_dependencies:
  - folder: lib/core/
    doc_summary: |  # Already-generated doc (bottom-up)
      Core utilities including TokenManager for JWT handling.
    public_api:
      - "class TokenManager"
      - "  Future<void> store(String token)"
    used_symbols:  # Which symbols this folder actually uses
      - TokenManager.store
      - TokenManager.retrieve

  - folder: lib/data/
    doc_summary: "Data layer with UserDao for persistence."
    public_api:
      - "class UserDao"
    used_symbols:
      - UserDao.saveUser

# EXTERNAL CONTEXT: Package dependencies
external_dependencies:
  - package: firebase_auth
    version: 4.6.0
    doc_summary: "Firebase Authentication SDK."  # From package README
    used_symbols:
      - FirebaseAuth.instance
      - FirebaseAuth.signInWithEmailAndPassword
      - UserCredential

  - package: shared_preferences
    version: 2.2.0
    doc_summary: "Persistent key-value storage."
    used_symbols:
      - SharedPreferences.getInstance

# WHO USES THIS: Dependents (for context)
dependents:
  - folder: lib/ui/auth/
    uses:
      - AuthService.login
      - AuthService.authStateChanges
```

### Context Layering

```
┌─────────────────────────────────────────────────────────────────┐
│                    Context for Folder A                          │
├─────────────────────────────────────────────────────────────────┤
│  FULL (current folder):                                          │
│    - All source files                                            │
│    - All doc comments                                            │
│    - Full SCIP symbol info                                       │
├─────────────────────────────────────────────────────────────────┤
│  SUMMARY (folder dependencies):                                  │
│    - Already-generated folder doc (compressed)                   │
│    - Public API signatures only                                  │
│    - Which specific symbols are used                             │
├─────────────────────────────────────────────────────────────────┤
│  EXTERNAL (package dependencies):                                │
│    - Package README / existing docs                              │
│    - Which specific symbols are used                             │
├─────────────────────────────────────────────────────────────────┤
│  MENTION (dependents):                                           │
│    - Just which symbols are called by whom                       │
└─────────────────────────────────────────────────────────────────┘
```

**Why this layering?**

1. **Token efficiency**: Full source for all deps would explode context
2. **Bottom-up**: Dependency docs generated first → use their summaries
3. **SCIP provides the graph**: We know exactly which symbols are called
4. **Avoid explosion**: Only direct dependencies, not transitive

## Bottom-Up Generation Flow

```
1. Build folder dependency graph
2. Topological sort (handle cycles with SCC)
3. Generate in order:

   Level 0 (no dependencies): lib/core/, lib/models/
      ↓ their docs become context for...
   Level 1: lib/data/, lib/services/
      ↓ their docs become context for...
   Level 2: lib/features/auth/, lib/features/products/
      ↓ their docs become context for...
   Level 3: lib/ui/
      ↓
   Module docs (synthesize folder docs)
      ↓
   Project doc (synthesize module docs)
```

## Manifest Schema

```json
{
  "version": 1,
  "folders": {
    "lib/features/auth/": {
      "structureHash": "abc123...",      // SCIP structure hash
      "docHash": "def456...",            // Hash of generated doc
      "generatedAt": "2025-01-12T10:00:00Z",
      "dependencies": {
        "internal": ["lib/core/", "lib/data/"],
        "external": ["firebase_auth@4.6.0", "shared_preferences@2.2.0"]
      },
      "smartSymbols": [
        "scip://lib/core/token_manager.dart/TokenManager#store",
        "scip://firebase_auth/.../FirebaseAuth#signInWithEmailAndPassword"
      ]
    }
  },
  "modules": {
    "auth": {
      "folders": ["lib/features/auth/", "lib/services/auth/", "lib/ui/auth/"],
      "docHash": "ghi789..."
    }
  }
}
```

## Dirty Detection Flow

```
On file save / git commit:

1. Reindex folder with SCIP (incremental)

2. Compute new structure hash:
   newHash = computeFolderStructureHash(folder, newIndex)

3. Compare with stored hash:
   if (newHash != manifest.folders[folder].structureHash) {
     // Structure changed - need LLM regeneration
     markDirtyForRegen(folder)
     propagateUp(folder)  // Module → Project
   }

4. Always re-resolve links (cheap):
   transformAllDocs(newIndex)
```

### Propagation Rules

```
UPWARD (always):
  Folder dirty → Module dirty → Project dirty

SIDEWAYS (via smart symbols):
  auth/ signature changes →
    For each folder F:
      If F has smart symbols pointing to changed auth/ symbols:
        markDirtyForRegen(F)
```

## LLM Output Structure

### Folder-Level Doc

```markdown
# Auth Feature

## Overview

The auth feature handles user authentication, session management, and 
credential persistence. It integrates with Firebase Auth for identity.

## Key Components

- [`AuthService`][auth-service] - Main authentication orchestrator
  - `login(email, password)` - Authenticate user credentials
  - `logout()` - Clear session and tokens
  - `authStateChanges` - Stream of authentication state

- [`AuthRepository`][auth-repo] - Data layer for auth operations

## How It Works

1. User enters credentials on [`LoginPage`][login-page]
2. [`AuthService.login()`][auth-login] validates and calls repository
3. On success, tokens stored via [`TokenManager`][token-mgr]
4. [`authStateChanges`][auth-stream] emits new state

## Dependencies

- **Internal**: [`TokenManager`][token-mgr] (core), [`UserDao`][user-dao] (data)
- **External**: `firebase_auth`, `shared_preferences`

<!-- Smart Symbol Definitions -->
[auth-service]: scip://lib/features/auth/auth_service.dart/AuthService#
[auth-repo]: scip://lib/features/auth/auth_repository.dart/AuthRepository#
[auth-login]: scip://lib/features/auth/auth_service.dart/AuthService#login().
[login-page]: scip://lib/ui/login_page.dart/LoginPage#
[token-mgr]: scip://lib/core/token_manager.dart/TokenManager#
[auth-stream]: scip://lib/features/auth/auth_service.dart/AuthService#authStateChanges.
[user-dao]: scip://lib/data/user_dao.dart/UserDao#
```

### Module-Level Doc

```markdown
# Auth Module

## Overview

Authentication and authorization for the application.

## Components

- [features/auth/](./folders/lib/features/auth/) - Core auth logic
- [services/auth/](./folders/lib/services/auth/) - Token & session mgmt
- [ui/auth/](./folders/lib/ui/auth/) - Login, signup screens

## Public API

- [`AuthService`][auth-service] - Primary interface
- [`AuthState`][auth-state] - State enum
- [`User`][user] - Authenticated user model

## Data Flow

```
LoginPage (UI)
    ↓ calls
AuthService (Service)
    ↓ calls
AuthRepository (Data)
    ↓ uses
Firebase Auth (External)
```

[auth-service]: scip://lib/features/auth/auth_service.dart/AuthService#
[auth-state]: scip://lib/features/auth/auth_state.dart/AuthState#
[user]: scip://lib/models/user.dart/User#
```

### Project-Level Doc

```markdown
# My Flutter App

## Overview

E-commerce application with user authentication, product catalog, 
and order management.

## Modules

- [Auth](./modules/auth.md) - User authentication
- [Products](./modules/products.md) - Product catalog
- [Core](./modules/core.md) - Shared utilities

## User Flows

### Authentication
[`SplashPage`][splash] → [`LoginPage`][login] → [`HomePage`][home]

### Shopping  
[`HomePage`][home] → [`ProductListPage`][products] → [`ProductDetailPage`][detail]

[splash]: scip://lib/ui/splash_page.dart/SplashPage#
[login]: scip://lib/ui/login_page.dart/LoginPage#
[home]: scip://lib/ui/home_page.dart/HomePage#
[products]: scip://lib/ui/product_list_page.dart/ProductListPage#
[detail]: scip://lib/ui/product_detail_page.dart/ProductDetailPage#
```

## CLI Commands (Planned)

```bash
# Generate/update docs (regenerates dirty, re-resolves all links)
code_context docs generate -p /path/to/project

# Force full regeneration (ignores structure hashes)
code_context docs generate -p /path/to/project --force

# Only re-resolve links (no LLM calls)
code_context docs resolve -p /path/to/project

# Show status (what's dirty, what needs regen)
code_context docs status -p /path/to/project

# Output style for rendered docs
code_context docs generate --link-style relative|github|absolute
```

## Design Decisions

### 1. Two-Stage Pipeline

**Problem**: LLM generation is expensive, but we want fresh links.

**Decision**: Separate concerns:
- Stage 1 (expensive): LLM generates docs with stable `scip://` URIs
- Stage 2 (cheap): Transform URIs to navigable file:line links

**Benefit**: Implementation changes only trigger cheap Stage 2.

### 2. Structure Hash from SCIP

**Problem**: File content hash triggers regen on any change (too aggressive).

**Decision**: Hash only documentation-relevant structure:
- Symbol names, kinds, signatures
- Doc comments
- Relationships

**Benefit**: Implementation body changes don't trigger regen.

### 3. Folder-Level Dependencies

**Problem**: File-level dependencies are too granular.

**Decision**: Aggregate imports to folder level:
- `lib/features/auth/` depends on `lib/core/`
- Use folder docs as dependency context, not individual files

**Benefit**: Simpler graph, better matches conceptual organization.

### 4. Bottom-Up with Topological Sort

**Problem**: Docs need dependency context, but what order?

**Decision**:
- Build folder dependency graph
- Topological sort (dependencies before dependents)
- Handle cycles with Tarjan's SCC (generate together)

**Benefit**: Each folder's doc can reference already-generated dependency docs.

### 5. External Package Context

**Decision**: Include existing package documentation (README, pub.dev):
- Note which symbols are used from each package
- Don't descend into package internals (expensive, low value)

**Future**: May generate docs for poorly-documented packages.

### 6. Agentic Generation

**Decision**: Use agent with tools rather than fixed pipeline:
- `read_file(path)` - Read source files
- `query_scip(query)` - Query the SCIP index
- `read_doc(path)` - Read already-generated folder docs
- `list_files(folder)` - Explore folder structure

**Benefit**: Agent handles large folders, non-Dart files, varying complexity.

### 7. Model Selection by Scope

| Scope | Model | Rationale |
|-------|-------|-----------|
| Folder docs | Cheaper (GPT-4o-mini, Haiku) | Many folders, simpler context |
| Module docs | Mid-tier (GPT-4o, Sonnet) | Synthesis from folder docs |
| Project docs | Premium (GPT-4, Opus) | High-level, most visible |

### 8. Primary Use Case: Agent Consumption

Docs are primarily for **AI agents** to quickly understand the codebase:
- Agent queries doc index to find relevant docs
- Reads docs (faster than reading all source files)
- Follows smart symbols to dive into code if needed

Secondary: Developer onboarding and reference.

## Comparison with DeepWiki/Code Wiki

| Aspect | code_context | DeepWiki/Others |
|--------|--------------|-----------------|
| Structure hash | SCIP-based (API changes only) | File-based? |
| Link resolution | Two-stage (cheap updates) | Embedded? |
| External packages | Docs as context | Single repo only |
| Dart expertise | Navigation, widgets, layers | Generic |
| Hosting | Local-first | Cloud service |

### Our Advantages

1. **Structure-aware dirty detection**: Only regen on API changes
2. **Cheap link updates**: Implementation changes don't need LLM
3. **Flutter semantics**: Navigation flows, widget layers
4. **Folder-level granularity**: Matches conceptual organization
5. **External package context**: Use existing docs efficiently

## Deferred (Future Consideration)

- Quality signals and validation
- CI/CD integration  
- Prompt customization / config files
- Generate docs for poorly-documented external packages

## Known Limitations

1. **No runtime information**: Static analysis only
2. **Complex generics**: May not fully explain type relationships
3. **Dynamic code**: Reflection, code generation not well documented
4. **Cross-repo**: Currently single-repo focused (monorepo OK)

## Implementation Status

- [ ] Structure hash computation from SCIP
- [ ] Folder dependency graph builder
- [ ] SCC detection for circular dependencies
- [ ] Topological sort for generation order
- [ ] Doc manifest schema and storage
- [ ] LLM context builder (folder → YAML)
- [ ] LLM synthesis pipeline (agentic)
- [ ] Smart symbol extraction from LLM output
- [ ] Link transformer (scip:// → file:line)
- [ ] Dirty detection and propagation
- [ ] CLI commands
- [ ] External package doc integration

## Related

- [Architecture](architecture.md) - System design
- [Flutter Navigation](flutter-navigation.md) - Navigation flow detection
- [Cross-Package Queries](cross-package-queries.md) - External package indexing
