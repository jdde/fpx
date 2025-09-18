import 'package:fpx/src/models/fpx_config.dart';
import 'package:test/test.dart';

void main() {
  group('FpxConfig', () {
    test('can be created with required parameters', () {
      final config = FpxConfig(
        bricks: BricksConfig(path: 'lib/src/components'),
        variables: VariablesConfig(
          foundation: FoundationConfig({
            'color': FoundationItem(path: 'lib/src/foundation/ui_colors.dart'),
          }),
        ),
      );

      expect(config.bricks.path, equals('lib/src/components'));
      expect(config.variables.foundation.items.length, equals(1));
      expect(config.variables.foundation.items['color']?.path, 
             equals('lib/src/foundation/ui_colors.dart'));
    });

    test('fromMap creates instance from map', () {
      final map = {
        'bricks': {
          'path': 'lib/src/widgets',
        },
        'variables': {
          'foundation': {
            'color': {
              'path': 'lib/src/foundation/colors.dart',
            },
            'spacing': {
              'path': 'lib/src/foundation/spacing.dart',
            },
          },
        },
      };

      final config = FpxConfig.fromMap(map);

      expect(config.bricks.path, equals('lib/src/widgets'));
      expect(config.variables.foundation.items.length, equals(2));
      expect(config.variables.foundation.items['color']?.path,
             equals('lib/src/foundation/colors.dart'));
      expect(config.variables.foundation.items['spacing']?.path,
             equals('lib/src/foundation/spacing.dart'));
    });

    test('defaultConfig creates instance with default values', () {
      final config = FpxConfig.defaultConfig();

      expect(config.bricks.path, equals('lib/src/components'));
      expect(config.variables.foundation.items.length, equals(4));
      expect(config.variables.foundation.items['color']?.path,
             equals('lib/src/foundation/ui_colors.dart'));
      expect(config.variables.foundation.items['spacing']?.path,
             equals('lib/src/foundation/ui_spacing.dart'));
      expect(config.variables.foundation.items['textStyles']?.path,
             equals('lib/src/foundation/ui_text_styles.dart'));
      expect(config.variables.foundation.items['radius']?.path,
             equals('lib/src/foundation/ui_radius.dart'));
    });

    test('toMap converts instance to map', () {
      final config = FpxConfig(
        bricks: BricksConfig(path: 'lib/components'),
        variables: VariablesConfig(
          foundation: FoundationConfig({
            'color': FoundationItem(path: 'lib/foundation/colors.dart'),
          }),
        ),
      );

      final map = config.toMap();

      expect(map['bricks'], isA<Map<String, dynamic>>());
      expect(map['bricks']['path'], equals('lib/components'));
      expect(map['variables'], isA<Map<String, dynamic>>());
      expect(map['variables']['foundation'], isA<Map<String, dynamic>>());
      expect(map['variables']['foundation']['color'], isA<Map<String, dynamic>>());
      expect(map['variables']['foundation']['color']['path'],
             equals('lib/foundation/colors.dart'));
    });
  });

  group('BricksConfig', () {
    test('can be created with path', () {
      final config = BricksConfig(path: 'lib/widgets');
      expect(config.path, equals('lib/widgets'));
    });

    test('fromMap creates instance from map', () {
      final map = {'path': 'lib/src/components'};
      final config = BricksConfig.fromMap(map);
      expect(config.path, equals('lib/src/components'));
    });

    test('toMap converts instance to map', () {
      final config = BricksConfig(path: 'lib/widgets');
      final map = config.toMap();
      expect(map, equals({'path': 'lib/widgets'}));
    });
  });

  group('VariablesConfig', () {
    test('can be created with foundation', () {
      final foundationConfig = FoundationConfig({
        'color': FoundationItem(path: 'lib/colors.dart'),
      });
      final config = VariablesConfig(foundation: foundationConfig);
      expect(config.foundation, equals(foundationConfig));
    });

    test('fromMap creates instance from map', () {
      final map = {
        'foundation': {
          'color': {'path': 'lib/colors.dart'},
          'spacing': {'path': 'lib/spacing.dart'},
        },
      };
      final config = VariablesConfig.fromMap(map);
      expect(config.foundation.items.length, equals(2));
      expect(config.foundation.items['color']?.path, equals('lib/colors.dart'));
      expect(config.foundation.items['spacing']?.path, equals('lib/spacing.dart'));
    });

    test('toMap converts instance to map', () {
      final foundationConfig = FoundationConfig({
        'color': FoundationItem(path: 'lib/colors.dart'),
      });
      final config = VariablesConfig(foundation: foundationConfig);
      final map = config.toMap();
      
      expect(map['foundation'], isA<Map<String, dynamic>>());
      expect(map['foundation']['color'], isA<Map<String, dynamic>>());
      expect(map['foundation']['color']['path'], equals('lib/colors.dart'));
    });
  });

  group('FoundationConfig', () {
    test('can be created with items map', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
        'spacing': FoundationItem(path: 'lib/spacing.dart'),
      };
      final config = FoundationConfig(items);
      expect(config.items, equals(items));
    });

    test('fromMap creates instance from map', () {
      final map = {
        'color': {'path': 'lib/colors.dart'},
        'spacing': {'path': 'lib/spacing.dart'},
        'typography': {'path': 'lib/typography.dart'},
      };
      final config = FoundationConfig.fromMap(map);
      
      expect(config.items.length, equals(3));
      expect(config.items['color']?.path, equals('lib/colors.dart'));
      expect(config.items['spacing']?.path, equals('lib/spacing.dart'));
      expect(config.items['typography']?.path, equals('lib/typography.dart'));
    });

    test('toMap converts instance to map', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
        'spacing': FoundationItem(path: 'lib/spacing.dart'),
      };
      final config = FoundationConfig(items);
      final map = config.toMap();
      
      expect(map['color'], isA<Map<String, dynamic>>());
      expect(map['color']['path'], equals('lib/colors.dart'));
      expect(map['spacing'], isA<Map<String, dynamic>>());
      expect(map['spacing']['path'], equals('lib/spacing.dart'));
    });

    test('entries returns list of map entries', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
        'spacing': FoundationItem(path: 'lib/spacing.dart'),
      };
      final config = FoundationConfig(items);
      final entries = config.entries;
      
      expect(entries.length, equals(2));
      expect(entries.any((e) => e.key == 'color'), isTrue);
      expect(entries.any((e) => e.key == 'spacing'), isTrue);
    });

    test('operator [] returns foundation item by key', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
        'spacing': FoundationItem(path: 'lib/spacing.dart'),
      };
      final config = FoundationConfig(items);
      
      expect(config['color']?.path, equals('lib/colors.dart'));
      expect(config['spacing']?.path, equals('lib/spacing.dart'));
      expect(config['nonexistent'], isNull);
    });

    test('containsKey returns true if key exists', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
      };
      final config = FoundationConfig(items);
      
      expect(config.containsKey('color'), isTrue);
      expect(config.containsKey('spacing'), isFalse);
    });

    test('paths returns list of all foundation file paths', () {
      final items = {
        'color': FoundationItem(path: 'lib/colors.dart'),
        'spacing': FoundationItem(path: 'lib/spacing.dart'),
        'typography': FoundationItem(path: 'lib/typography.dart'),
      };
      final config = FoundationConfig(items);
      final paths = config.paths;
      
      expect(paths.length, equals(3));
      expect(paths.contains('lib/colors.dart'), isTrue);
      expect(paths.contains('lib/spacing.dart'), isTrue);
      expect(paths.contains('lib/typography.dart'), isTrue);
    });
  });

  group('FoundationItem', () {
    test('can be created with path', () {
      final item = FoundationItem(path: 'lib/colors.dart');
      expect(item.path, equals('lib/colors.dart'));
    });

    test('fromMap creates instance from map', () {
      final map = {'path': 'lib/spacing.dart'};
      final item = FoundationItem.fromMap(map);
      expect(item.path, equals('lib/spacing.dart'));
    });

    test('toMap converts instance to map', () {
      final item = FoundationItem(path: 'lib/typography.dart');
      final map = item.toMap();
      expect(map, equals({'path': 'lib/typography.dart'}));
    });
  });
}
