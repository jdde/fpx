/// Model class representing the fpx configuration structure.
/// 
/// This class defines the structure for fpx configuration that specifies
/// how bricks and variables should be handled in repositories.
class FpxConfig {
  /// Constructor
  const FpxConfig({
    required this.bricks,
    required this.variables,
  });

  /// Creates FpxConfig from a Map (typically parsed from YAML).
  factory FpxConfig.fromMap(Map<String, dynamic> map) {
    return FpxConfig(
      bricks: BricksConfig.fromMap(map['bricks'] as Map<String, dynamic>),
      variables: VariablesConfig.fromMap(map['variables'] as Map<String, dynamic>),
    );
  }

  /// Creates a default FpxConfig with standard Flutter project structure.
  factory FpxConfig.defaultConfig() {
    return FpxConfig(
      bricks: BricksConfig(path: 'lib/src/components'),
      variables: VariablesConfig(
        foundation: FoundationConfig({
          'color': FoundationItem(path: 'lib/src/foundation/ui_colors.dart'),
          'spacing': FoundationItem(path: 'lib/src/foundation/ui_spacing.dart'),
          'textStyles': FoundationItem(path: 'lib/src/foundation/ui_text_styles.dart'),
          'radius': FoundationItem(path: 'lib/src/foundation/ui_radius.dart'),
        }),
      ),
    );
  }

  /// Bricks configuration
  final BricksConfig bricks;

  /// Variables configuration
  final VariablesConfig variables;

  /// Converts this config to a Map.
  Map<String, dynamic> toMap() {
    return {
      'bricks': bricks.toMap(),
      'variables': variables.toMap(),
    };
  }
}

/// Configuration for bricks.
class BricksConfig {
  /// Constructor
  const BricksConfig({
    required this.path,
  });

  /// Creates BricksConfig from a Map.
  factory BricksConfig.fromMap(Map<String, dynamic> map) {
    return BricksConfig(
      path: map['path'] as String,
    );
  }

  /// Path where bricks/components are located
  final String path;

  /// Converts this config to a Map.
  Map<String, dynamic> toMap() {
    return {
      'path': path,
    };
  }
}

/// Configuration for variables.
class VariablesConfig {
  /// Constructor
  const VariablesConfig({
    required this.foundation,
  });

  /// Creates VariablesConfig from a Map.
  factory VariablesConfig.fromMap(Map<String, dynamic> map) {
    return VariablesConfig(
      foundation: FoundationConfig.fromMap(map['foundation'] as Map<String, dynamic>),
    );
  }

  /// Foundation configuration
  final FoundationConfig foundation;

  /// Converts this config to a Map.
  Map<String, dynamic> toMap() {
    return {
      'foundation': foundation.toMap(),
    };
  }
}

/// Configuration for foundation elements.
/// 
/// Uses a flexible Map-based approach to support any foundation file keys.
class FoundationConfig {
  /// Constructor
  const FoundationConfig(this.items);

  /// Creates FoundationConfig from a Map.
  factory FoundationConfig.fromMap(Map<String, dynamic> map) {
    final items = <String, FoundationItem>{};
    
    for (final entry in map.entries) {
      items[entry.key] = FoundationItem.fromMap(entry.value as Map<String, dynamic>);
    }
    
    return FoundationConfig(items);
  }

  /// Map of foundation item keys to their configurations
  final Map<String, FoundationItem> items;

  /// Converts this config to a Map.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    for (final entry in items.entries) {
      map[entry.key] = entry.value.toMap();
    }
    
    return map;
  }

  /// Get all foundation items as a list
  List<MapEntry<String, FoundationItem>> get entries => items.entries.toList();

  /// Get a foundation item by key
  FoundationItem? operator [](String key) => items[key];

  /// Check if a foundation item exists
  bool containsKey(String key) => items.containsKey(key);

  /// Get all foundation file paths
  List<String> get paths => items.values.map((item) => item.path).toList();
}

/// Configuration for individual foundation items.
class FoundationItem {
  /// Constructor
  const FoundationItem({
    required this.path,
  });

  /// Creates FoundationItem from a Map.
  factory FoundationItem.fromMap(Map<String, dynamic> map) {
    return FoundationItem(
      path: map['path'] as String,
    );
  }

  /// Path to the foundation file
  final String path;

  /// Converts this config to a Map.
  Map<String, dynamic> toMap() {
    return {
      'path': path,
    };
  }
}
