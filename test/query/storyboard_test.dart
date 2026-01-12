import 'package:scip_server/src/query/query_result.dart';
import 'package:test/test.dart';

void main() {
  group('StoryboardResult', () {
    group('toText', () {
      test('generates mermaid diagram by default', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth'),
            ScreenInfo(name: 'HomePage', feature: 'main'),
            ScreenInfo(name: 'SettingsPage', feature: 'settings'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              trigger: 'push',
            ),
            NavigationEdgeInfo(
              fromScreen: 'HomePage',
              toScreen: 'SettingsPage',
              trigger: 'push',
            ),
          ],
          routerType: 'navigator',
          entryScreen: 'LoginPage',
        );

        final text = result.toText();

        expect(text, contains('## Navigation Storyboard'));
        expect(text, contains('3 screens'));
        expect(text, contains('2 navigation edges'));
        expect(text, contains('Router: navigator'));
        expect(text, contains('Entry: LoginPage'));
        expect(text, contains('```mermaid'));
        expect(text, contains('flowchart TD'));
        expect(text, contains('LoginPage'));
        expect(text, contains('HomePage'));
        expect(text, contains('SettingsPage'));
      });

      test('generates ascii diagram when format is ascii', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage'),
            ScreenInfo(name: 'HomePage'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
            ),
          ],
          routerType: 'navigator',
          format: 'ascii',
        );

        final text = result.toText();

        expect(text, contains('Navigation Flow'));
        expect(text, contains('LoginPage'));
        expect(text, contains('HomePage'));
        expect(text, isNot(contains('```mermaid')));
      });

      test('handles empty screens', () {
        const result = StoryboardResult(
          screens: [],
          edges: [],
          routerType: 'unknown',
        );

        expect(result.isEmpty, isTrue);
        expect(result.toText(), contains('No screens found'));
      });
    });

    group('toJson', () {
      test('includes all fields', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth', file: 'lib/login.dart'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              trigger: 'push',
              routePath: '/home',
            ),
          ],
          routerType: 'goRouter',
          entryScreen: 'LoginPage',
        );

        final json = result.toJson();

        expect(json['type'], 'storyboard');
        expect(json['screenCount'], 1);
        expect(json['edgeCount'], 1);
        expect(json['routerType'], 'goRouter');
        expect(json['entryScreen'], 'LoginPage');
        expect(json['screens'], hasLength(1));
        expect(json['screens'][0]['name'], 'LoginPage');
        expect(json['screens'][0]['feature'], 'auth');
        expect(json['edges'], hasLength(1));
        expect(json['edges'][0]['from'], 'LoginPage');
        expect(json['edges'][0]['to'], 'HomePage');
        expect(json['edges'][0]['routePath'], '/home');
        expect(json['mermaid'], contains('flowchart TD'));
      });
    });

    group('mermaid generation', () {
      test('uses subgraphs when multiple features exist', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth'),
            ScreenInfo(name: 'SignupPage', feature: 'auth'),
            ScreenInfo(name: 'HomePage', feature: 'main'),
          ],
          edges: [
            NavigationEdgeInfo(fromScreen: 'LoginPage', toScreen: 'SignupPage'),
            NavigationEdgeInfo(fromScreen: 'LoginPage', toScreen: 'HomePage'),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();
        final mermaid = json['mermaid'] as String;

        expect(mermaid, contains('subgraph'));
        expect(mermaid, contains('[auth]'));
        expect(mermaid, contains('[main]'));
      });

      test('includes edge labels when present', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage'),
            ScreenInfo(name: 'HomePage'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              label: 'on success',
            ),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();
        final mermaid = json['mermaid'] as String;

        expect(mermaid, contains('on success'));
      });

      test('sanitizes node IDs', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'Login-Page'),
            ScreenInfo(name: 'Home Page'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'Login-Page',
              toScreen: 'Home Page',
            ),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();
        final mermaid = json['mermaid'] as String;

        // Dashes and spaces should be converted to underscores
        expect(mermaid, contains('Login_Page'));
        expect(mermaid, contains('Home_Page'));
      });
    });
  });

  group('ClassifyResult', () {
    group('toText', () {
      test('groups symbols by layer', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#LoginPage',
              name: 'LoginPage',
              layer: 'ui',
              feature: 'auth',
              confidence: 0.9,
              file: 'lib/login.dart',
            ),
            SymbolClassificationInfo(
              symbolId: 'test#AuthService',
              name: 'AuthService',
              layer: 'service',
              feature: 'auth',
              confidence: 0.85,
              file: 'lib/auth.dart',
            ),
            SymbolClassificationInfo(
              symbolId: 'test#UserRepository',
              name: 'UserRepository',
              layer: 'data',
              feature: 'user',
              confidence: 0.95,
              file: 'lib/user_repo.dart',
            ),
          ],
        );

        final text = result.toText();

        expect(text, contains('## Symbol Classification (3 symbols)'));
        expect(text, contains('### UI Layer'));
        expect(text, contains('### Service Layer'));
        expect(text, contains('### Data Layer'));
        expect(text, contains('LoginPage'));
        expect(text, contains('AuthService'));
        expect(text, contains('UserRepository'));
      });

      test('handles empty classifications', () {
        const result = ClassifyResult(classifications: []);

        expect(result.isEmpty, isTrue);
        expect(result.toText(), contains('No symbols found'));
      });

      test('shows markdown table format', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#MyService',
              name: 'MyService',
              layer: 'service',
              feature: 'core',
              confidence: 0.8,
              file: 'lib/service.dart',
            ),
          ],
        );

        final text = result.toText();

        expect(text, contains('| Symbol | Feature | File |'));
        expect(text, contains('|--------|---------|------|'));
        expect(text, contains('| MyService | core | lib/service.dart |'));
      });
    });

    group('toJson', () {
      test('includes all fields', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#AuthService',
              name: 'AuthService',
              layer: 'service',
              feature: 'auth',
              confidence: 0.9,
              file: 'lib/auth.dart',
              signals: ['name pattern → service'],
            ),
          ],
          pattern: '*Service',
        );

        final json = result.toJson();

        expect(json['type'], 'classify');
        expect(json['count'], 1);
        expect(json['pattern'], '*Service');
        expect(json['classifications'], hasLength(1));
        
        final c = json['classifications'][0] as Map<String, dynamic>;
        expect(c['symbol'], 'test#AuthService');
        expect(c['name'], 'AuthService');
        expect(c['layer'], 'service');
        expect(c['feature'], 'auth');
        expect(c['confidence'], 0.9);
        expect(c['file'], 'lib/auth.dart');
        expect(c['signals'], contains('name pattern → service'));
      });
    });
  });
}
