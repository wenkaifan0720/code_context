import 'dart:io';

import 'package:protobuf/protobuf.dart' show CodedBufferReader;
// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;

import '../index/scip_index.dart';
import 'sql_index.dart';

/// Converts SCIP protobuf data to SQL and populates a SqlIndex.
///
/// Handles:
/// - Parsing SCIP symbol IDs to extract package/version/name
/// - Building parent-child relationships from symbol paths
/// - Constructing call graph from occurrence data
/// - Batch inserts for performance
///
/// ## Usage
///
/// ```dart
/// final db = SqlIndex.inMemory();
/// final converter = ScipToSql(db);
///
/// // Load project index
/// await converter.loadFromFile('project.scip', projectRoot: '/my/project');
///
/// // Load external package indexes
/// await converter.loadFromFile('flutter.scip', projectRoot: '/flutter/packages/flutter');
/// ```
class ScipToSql {
  ScipToSql(this._db);

  final SqlIndex _db;

  /// Default maximum size for protobuf index files (256MB).
  static const int defaultMaxIndexSize = 256 << 20;

  /// Load a SCIP index file and insert its data into the database.
  Future<void> loadFromFile(
    String indexPath, {
    required String projectRoot,
    String? sourceRoot,
    int maxSize = defaultMaxIndexSize,
  }) async {
    final bytes = await File(indexPath).readAsBytes();
    final reader = CodedBufferReader(bytes, sizeLimit: maxSize);
    final index = scip.Index()..mergeFromCodedBufferReader(reader);
    loadFromScipProtobuf(index, projectRoot: projectRoot, sourceRoot: sourceRoot);
  }

  /// Load SCIP protobuf data and insert into the database.
  void loadFromScipProtobuf(
    scip.Index raw, {
    required String projectRoot,
    String? sourceRoot,
  }) {
    _db.beginTransaction();
    try {
      // Track definitions with ranges for call graph building
      final definitionsInFile =
          <String, List<({String symbol, int startLine, int endLine})>>{};

      // Process documents (files)
      for (final doc in raw.documents) {
        final filePath = doc.relativePath;

        // First pass: index symbols
        for (final sym in doc.symbols) {
          _insertSymbol(sym, file: filePath, language: doc.language);
        }

        // Second pass: index occurrences and collect definitions
        final fileDefinitions =
            <({String symbol, int startLine, int endLine})>[];

        for (final occ in doc.occurrences) {
          final isDefinition =
              (occ.symbolRoles & scip.SymbolRole.Definition.value) != 0;

          _insertOccurrence(occ, file: filePath, isDefinition: isDefinition);

          // Track definitions with enclosing ranges for call graph
          if (isDefinition && occ.enclosingRange.isNotEmpty) {
            final startLine = occ.range.isNotEmpty ? occ.range[0] : 0;
            final endLine = occ.enclosingRange.length > 2
                ? occ.enclosingRange[2]
                : startLine;
            fileDefinitions.add((
              symbol: occ.symbol,
              startLine: startLine,
              endLine: endLine,
            ));
          }
        }

        definitionsInFile[filePath] = fileDefinitions;
      }

      // Build call graph from reference occurrences
      for (final doc in raw.documents) {
        final filePath = doc.relativePath;
        final fileDefinitions = definitionsInFile[filePath] ?? [];

        for (final occ in doc.occurrences) {
          final isReference =
              (occ.symbolRoles & scip.SymbolRole.Definition.value) == 0;
          if (!isReference) continue;

          final refLine = occ.range.isNotEmpty ? occ.range[0] : 0;
          final referencedSymbol = occ.symbol;

          // Find which definition contains this reference
          for (final def in fileDefinitions) {
            if (refLine >= def.startLine && refLine <= def.endLine) {
              // def.symbol calls referencedSymbol
              _insertRelationship(def.symbol, referencedSymbol, 'calls');
              break;
            }
          }
        }
      }

      // Index external symbols (from dependencies)
      for (final sym in raw.externalSymbols) {
        _insertSymbol(sym, file: null, language: null);
      }

      _db.commit();
    } catch (e) {
      _db.rollback();
      rethrow;
    }
  }

  /// Insert a symbol into the database.
  void _insertSymbol(
    scip.SymbolInformation sym, {
    String? file,
    String? language,
  }) {
    final parsed = _parseSymbolId(sym.symbol);
    final containerId = _extractParentSymbol(sym.symbol);

    // Insert symbol
    _db.execute(
      '''
      INSERT OR REPLACE INTO symbols 
        (scip_id, name, kind, file, package, version, container_id, 
         display_name, documentation, language)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sym.symbol,
        parsed.name,
        _kindToString(sym.kind),
        file,
        parsed.package,
        parsed.version,
        containerId,
        sym.displayName.isNotEmpty ? sym.displayName : null,
        sym.documentation.isNotEmpty ? sym.documentation.join('\n') : null,
        language,
      ],
    );

    // Insert relationships from symbol info
    for (final rel in sym.relationships) {
      if (rel.isImplementation) {
        _insertRelationship(sym.symbol, rel.symbol, 'implements');
      }
      if (rel.isTypeDefinition) {
        _insertRelationship(sym.symbol, rel.symbol, 'type_definition');
      }
      if (rel.isReference) {
        _insertRelationship(sym.symbol, rel.symbol, 'references');
      }
    }
  }

  /// Insert an occurrence into the database.
  void _insertOccurrence(
    scip.Occurrence occ, {
    required String file,
    required bool isDefinition,
  }) {
    final range = occ.range;
    final startLine = range.isNotEmpty ? range[0] : 0;
    final startChar = range.length > 1 ? range[1] : 0;
    final endLine = range.length > 3 ? range[2] : startLine;
    final endChar =
        range.length > 3 ? range[3] : (range.length > 2 ? range[2] : startChar);

    final enclosing = occ.enclosingRange;
    final enclosingEnd = enclosing.length > 2 ? enclosing[2] : null;

    _db.execute(
      '''
      INSERT INTO occurrences 
        (symbol_id, file, line, column_num, end_line, end_column, 
         is_definition, enclosing_end_line)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        occ.symbol,
        file,
        startLine,
        startChar,
        endLine,
        endChar,
        isDefinition ? 1 : 0,
        enclosingEnd,
      ],
    );

    // Update symbol's line/column if this is the definition
    if (isDefinition) {
      _db.execute(
        '''
        UPDATE symbols 
        SET line = ?, column_num = ?
        WHERE scip_id = ? AND line IS NULL
        ''',
        [startLine, startChar, occ.symbol],
      );
    }
  }

  /// Insert a relationship into the database.
  void _insertRelationship(String fromSymbol, String toSymbol, String kind) {
    _db.execute(
      '''
      INSERT OR IGNORE INTO relationships (from_symbol, to_symbol, kind)
      VALUES (?, ?, ?)
      ''',
      [fromSymbol, toSymbol, kind],
    );
  }

  /// Parse a SCIP symbol ID into its components.
  ///
  /// SCIP format: `scip-dart pub package_name version path/Class#method().`
  ({String? package, String? version, String name}) _parseSymbolId(
      String symbol) {
    // Extract name - try different patterns

    // Getter/setter: `<get>name`. or `<set>name`.
    final getterMatch = RegExp(r'`<(get|set)>([^`]+)`\.?$').firstMatch(symbol);
    if (getterMatch != null) {
      return (
        package: _extractPackage(symbol),
        version: _extractVersion(symbol),
        name: getterMatch.group(2)!,
      );
    }

    // Constructor: `<constructor>`().
    final ctorMatch = RegExp(r'`<constructor>`\(\)\.?$').firstMatch(symbol);
    if (ctorMatch != null) {
      final classMatch =
          RegExp(r'/([A-Za-z_][A-Za-z0-9_]*)#').firstMatch(symbol);
      return (
        package: _extractPackage(symbol),
        version: _extractVersion(symbol),
        name: classMatch?.group(1) ?? 'constructor',
      );
    }

    // Backtick-escaped name: `name`.
    final backtickMatch = RegExp(r'`([^`]+)`\.?$').firstMatch(symbol);
    if (backtickMatch != null) {
      return (
        package: _extractPackage(symbol),
        version: _extractVersion(symbol),
        name: backtickMatch.group(1)!,
      );
    }

    // Standard name
    final match =
        RegExp(r'([A-Za-z_][A-Za-z0-9_]*)[\.\#\(\)\[\]]*$').firstMatch(symbol);
    return (
      package: _extractPackage(symbol),
      version: _extractVersion(symbol),
      name: match?.group(1) ?? symbol,
    );
  }

  /// Extract package name from SCIP symbol.
  String? _extractPackage(String symbol) {
    // Format: scip-dart pub package_name version ...
    final match = RegExp(r'^scip-dart pub ([^ ]+) ').firstMatch(symbol);
    return match?.group(1);
  }

  /// Extract version from SCIP symbol.
  String? _extractVersion(String symbol) {
    // Format: scip-dart pub package_name version ...
    final match = RegExp(r'^scip-dart pub [^ ]+ ([^ ]+) ').firstMatch(symbol);
    return match?.group(1);
  }

  /// Extract parent symbol from SCIP symbol string.
  String? _extractParentSymbol(String symbol) {
    final lastSlash = symbol.lastIndexOf('/');
    final lastHash = symbol.lastIndexOf('#');

    // Method of a class: Parent is everything up to and including #
    if (lastHash > lastSlash) {
      final afterHash = symbol.substring(lastHash + 1);
      if (afterHash.isNotEmpty) {
        return symbol.substring(0, lastHash + 1);
      }
    }

    return null;
  }

  /// Load from a ScipIndex (in-memory index).
  ///
  /// This is used when building SQL from already-loaded SCIP data.
  void loadFromScipIndex(ScipIndex index) {
    _db.beginTransaction();
    try {
      // Load all symbols
      for (final sym in index.allSymbols) {
        _insertSymbolInfo(sym);

        // Load occurrences for this symbol
        final def = index.findDefinition(sym.symbol);
        if (def != null) {
          _insertOccurrenceInfo(def);
        }

        for (final ref in index.findReferences(sym.symbol)) {
          _insertOccurrenceInfo(ref);
        }

        // Load call graph relationships
        for (final called in index.getCalls(sym.symbol)) {
          _insertRelationship(sym.symbol, called.symbol, 'calls');
        }
      }
      _db.commit();
    } catch (e) {
      _db.rollback();
      rethrow;
    }
  }

  /// Load from in-memory SymbolInfo objects (from ScipIndex).
  ///
  /// This is used when building SQL from already-loaded SCIP data.
  /// For full data including occurrences, use [loadFromScipIndex] instead.
  void loadFromScipIndexData({
    required Iterable<SymbolInfo> symbols,
    required String projectRoot,
  }) {
    _db.beginTransaction();
    try {
      for (final sym in symbols) {
        _insertSymbolInfo(sym);
      }
      _db.commit();
    } catch (e) {
      _db.rollback();
      rethrow;
    }
  }

  /// Insert an OccurrenceInfo into the database.
  void _insertOccurrenceInfo(OccurrenceInfo occ) {
    _db.execute(
      '''
      INSERT INTO occurrences 
        (symbol_id, file, line, column_num, end_line, end_column, 
         is_definition, enclosing_end_line)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        occ.symbol,
        occ.file,
        occ.line,
        occ.column,
        occ.endLine,
        occ.endColumn,
        occ.isDefinition ? 1 : 0,
        occ.enclosingEndLine,
      ],
    );

    // Update symbol's line/column if this is the definition
    if (occ.isDefinition) {
      _db.execute(
        '''
        UPDATE symbols 
        SET line = ?, column_num = ?
        WHERE scip_id = ? AND line IS NULL
        ''',
        [occ.line, occ.column, occ.symbol],
      );
    }
  }

  /// Insert a SymbolInfo into the database.
  void _insertSymbolInfo(SymbolInfo sym) {
    final parsed = _parseSymbolId(sym.symbol);
    final containerId = _extractParentSymbol(sym.symbol);

    _db.execute(
      '''
      INSERT OR REPLACE INTO symbols 
        (scip_id, name, kind, file, package, version, container_id, 
         display_name, documentation, language)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sym.symbol,
        sym.name,
        sym.kindString,
        sym.file,
        parsed.package,
        parsed.version,
        containerId,
        sym.displayName,
        sym.documentation.isNotEmpty ? sym.documentation.join('\n') : null,
        sym.language,
      ],
    );

    // Insert relationships
    for (final rel in sym.relationships) {
      if (rel.isImplementation) {
        _insertRelationship(sym.symbol, rel.symbol, 'implements');
      }
      if (rel.isTypeDefinition) {
        _insertRelationship(sym.symbol, rel.symbol, 'type_definition');
      }
      if (rel.isReference) {
        _insertRelationship(sym.symbol, rel.symbol, 'references');
      }
    }
  }

  /// Convert SCIP kind enum to string.
  String _kindToString(scip.SymbolInformation_Kind kind) {
    switch (kind) {
      case scip.SymbolInformation_Kind.Class:
        return 'class';
      case scip.SymbolInformation_Kind.Method:
        return 'method';
      case scip.SymbolInformation_Kind.Function:
        return 'function';
      case scip.SymbolInformation_Kind.Field:
        return 'field';
      case scip.SymbolInformation_Kind.Constructor:
        return 'constructor';
      case scip.SymbolInformation_Kind.Enum:
        return 'enum';
      case scip.SymbolInformation_Kind.EnumMember:
        return 'enumMember';
      case scip.SymbolInformation_Kind.Interface:
        return 'interface';
      case scip.SymbolInformation_Kind.Variable:
        return 'variable';
      case scip.SymbolInformation_Kind.Property:
        return 'property';
      case scip.SymbolInformation_Kind.Parameter:
        return 'parameter';
      case scip.SymbolInformation_Kind.Mixin:
        return 'mixin';
      case scip.SymbolInformation_Kind.Extension:
        return 'extension';
      case scip.SymbolInformation_Kind.Getter:
        return 'getter';
      case scip.SymbolInformation_Kind.Setter:
        return 'setter';
      default:
        return kind.name.toLowerCase();
    }
  }
}
