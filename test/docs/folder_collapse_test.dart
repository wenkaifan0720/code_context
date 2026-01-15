import 'dart:io';

import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('CollapseConfig', () {
    test('default values', () {
      const config = CollapseConfig();
      expect(config.lineThreshold, 500);
      expect(config.hysteresisLow, 450);
      expect(config.hysteresisHigh, 550);
      expect(config.maxDepth, 3);
      expect(config.enabled, true);
    });

    test('disabled config', () {
      const config = CollapseConfig.disabled;
      expect(config.enabled, false);
    });
  });

  group('CollapseDecision', () {
    test('none constructor', () {
      const decision = CollapseDecision.none();
      expect(decision.collapsedRoots, isEmpty);
      expect(decision.childToRoot, isEmpty);
      expect(decision.expandedFolders, isEmpty);
      expect(decision.foldersToGenerate, isEmpty);
    });

    test('isCollapsedRoot', () {
      final decision = CollapseDecision(
        collapsedRoots: {'lib/features/auth'},
        childToRoot: {'lib/features/auth/models': 'lib/features/auth'},
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      expect(decision.isCollapsedRoot('lib/features/auth'), true);
      expect(decision.isCollapsedRoot('lib/core'), false);
      expect(decision.isCollapsedRoot('lib/features/auth/models'), false);
    });

    test('isCollapsedChild', () {
      final decision = CollapseDecision(
        collapsedRoots: {'lib/features/auth'},
        childToRoot: {'lib/features/auth/models': 'lib/features/auth'},
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      expect(decision.isCollapsedChild('lib/features/auth/models'), true);
      expect(decision.isCollapsedChild('lib/features/auth'), false);
      expect(decision.isCollapsedChild('lib/core'), false);
    });

    test('getCollapseRoot', () {
      final decision = CollapseDecision(
        collapsedRoots: {'lib/features/auth'},
        childToRoot: {'lib/features/auth/models': 'lib/features/auth'},
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      expect(decision.getCollapseRoot('lib/features/auth'), 'lib/features/auth');
      expect(
          decision.getCollapseRoot('lib/features/auth/models'), 'lib/features/auth');
      expect(decision.getCollapseRoot('lib/core'), null);
    });

    test('foldersToGenerate', () {
      final decision = CollapseDecision(
        collapsedRoots: {'lib/features/auth'},
        childToRoot: {'lib/features/auth/models': 'lib/features/auth'},
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      expect(
        decision.foldersToGenerate,
        {'lib/features/auth', 'lib/core'},
      );
    });

    test('getCollapsedSubfolders', () {
      final decision = CollapseDecision(
        collapsedRoots: {'lib/features/auth'},
        childToRoot: {
          'lib/features/auth/models': 'lib/features/auth',
          'lib/features/auth/services': 'lib/features/auth',
        },
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      expect(
        decision.getCollapsedSubfolders('lib/features/auth'),
        containsAll(['lib/features/auth/models', 'lib/features/auth/services']),
      );
      expect(decision.getCollapsedSubfolders('lib/core'), isEmpty);
    });
  });

  group('FolderDocState with collapse', () {
    test('serialization with collapse fields', () {
      final state = FolderDocState(
        structureHash: 'abc123',
        docHash: 'def456',
        generatedAt: DateTime(2024, 1, 15),
        isCollapsed: true,
        collapsedSubfolders: ['sub1', 'sub2'],
      );

      final json = state.toJson();
      expect(json['isCollapsed'], true);
      expect(json['collapsedSubfolders'], ['sub1', 'sub2']);

      final restored = FolderDocState.fromJson(json);
      expect(restored.isCollapsed, true);
      expect(restored.collapsedSubfolders, ['sub1', 'sub2']);
    });

    test('serialization without collapse fields', () {
      final state = FolderDocState(
        structureHash: 'abc123',
        docHash: 'def456',
        generatedAt: DateTime(2024, 1, 15),
      );

      final json = state.toJson();
      expect(json.containsKey('isCollapsed'), false);
      expect(json.containsKey('collapsedSubfolders'), false);

      final restored = FolderDocState.fromJson(json);
      expect(restored.isCollapsed, false);
      expect(restored.collapsedSubfolders, isEmpty);
    });
  });

  group('DocManifest collapse helpers', () {
    test('getPreviousCollapseState', () {
      final manifest = DocManifest(
        folders: {
          'lib/auth': FolderDocState(
            structureHash: 'a',
            docHash: 'b',
            generatedAt: DateTime.now(),
            isCollapsed: true,
          ),
          'lib/core': FolderDocState(
            structureHash: 'c',
            docHash: 'd',
            generatedAt: DateTime.now(),
            isCollapsed: false,
          ),
        },
      );

      final state = manifest.getPreviousCollapseState();
      expect(state['lib/auth'], true);
      expect(state['lib/core'], false);
    });

    test('getCollapsedChildren', () {
      final manifest = DocManifest(
        folders: {
          'lib/auth': FolderDocState(
            structureHash: 'a',
            docHash: 'b',
            generatedAt: DateTime.now(),
            isCollapsed: true,
            collapsedSubfolders: ['lib/auth/models', 'lib/auth/services'],
          ),
        },
      );

      final children = manifest.getCollapsedChildren();
      expect(children, containsAll(['lib/auth/models', 'lib/auth/services']));
    });
  });

  group('DirtyTracker with collapse', () {
    test('createFolderState with collapse', () {
      final state = DirtyTracker.createFolderState(
        structureHash: 'hash123',
        docContent: '# Test\n\nContent',
        internalDeps: ['lib/core'],
        externalDeps: ['flutter'],
        smartSymbols: ['scip://lib/auth.dart/Auth#'],
        isCollapsed: true,
        collapsedSubfolders: ['lib/auth/models'],
      );

      expect(state.isCollapsed, true);
      expect(state.collapsedSubfolders, ['lib/auth/models']);
      expect(state.structureHash, 'hash123');
    });
  });

  group('DirtyState with collapse', () {
    test('toSummary includes collapse info', () {
      final collapseDecision = CollapseDecision(
        collapsedRoots: {'lib/auth'},
        childToRoot: {'lib/auth/models': 'lib/auth'},
        expandedFolders: {'lib/core'},
        folderLineCounts: {},
      );

      final state = DirtyState(
        dirtyFolders: {'lib/auth'},
        dirtyModules: {},
        projectDirty: false,
        generationOrder: [
          ['lib/auth']
        ],
        structureHashes: {'lib/auth': 'hash'},
        collapseDecision: collapseDecision,
      );

      final summary = state.toSummary();
      expect(summary['collapsedRoots'], 1);
      expect(summary['collapsedChildren'], 1);
    });
  });

  group('FolderDependencyGraph collapse detection', () {
    test('depth limit detection', () async {
      // Create a graph with deep nesting
      final graph = FolderDependencyGraph.forTesting(
        folders: {
          'lib',
          'lib/features',
          'lib/features/auth',
          'lib/features/auth/models',
          'lib/features/auth/models/entities', // 4 levels deep
        },
        internalDeps: {},
      );

      final decision = await graph.computeCollapseDecision(
        config: const CollapseConfig(
          lineThreshold: 10000, // High threshold, won't trigger
          maxDepth: 3, // Will trigger for entities
        ),
        projectRoot: Directory.systemTemp.path,
      );

      // entities is 4 levels deep under lib, should be collapsed
      // But since there's nothing above it that's under threshold,
      // the parent (models) should be the collapse root
      // Actually, since entities exceeds depth, it should be collapsed
      expect(
        decision.collapsedRoots.any((r) => r.contains('entities') || r.contains('models')),
        true,
        reason: 'Deep folders should trigger collapse',
      );
    });
  });
}
