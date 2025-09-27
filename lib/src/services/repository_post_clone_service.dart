import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../models/models.dart';

/// Service for manipulating cloned repositories after they are cloned.
/// 
/// This service adds custom logic to process repositories immediately
/// after they are cloned, such as adding __brick__ directories or
/// other custom modifications.
class RepositoryPostCloneService {
  /// Constructor
  const RepositoryPostCloneService({
    required Logger logger,
  }) : _logger = logger;

  final Logger _logger;

  /// Process a cloned repository by applying custom manipulations.
  /// 
  /// This method is called after a repository is successfully cloned
  /// and applies various transformations to the cloned repository.
  /// 
  /// [repositoryName] - The name of the repository
  /// [repositoryPath] - The local path where the repository was cloned
  /// [repositoryUrl] - The original URL of the repository
  /// [fpxConfig] - The fpx configuration object. If null, uses default config.
  Future<void> processClonedRepository({
    required String repositoryName,
    required String repositoryPath,
    required String repositoryUrl,
    FpxConfig? fpxConfig,
  }) async {
    _logger.info('🔧 Processing cloned repository "$repositoryName"...');

    // Use provided config or default config
    final config = fpxConfig ?? FpxConfig.defaultConfig();

    try {
      // Add __brick__ to the repository
      await _addBricksToRepository(repositoryPath, config);
      
      // Resolve cross-component dependencies in bricks
      await _resolveBrickDependencies(repositoryPath, config);
      
      // Future: Add other custom manipulations here
      // await _addCustomConfigurations(repositoryPath, config);
      // await _setupCustomStructure(repositoryPath, config);
      
      _logger.success('✅ Repository processing completed successfully');
    } catch (e) {
      _logger.warn('⚠️  Failed to process repository: $e'); // coverage:ignore-line
      // Don't throw - repository is still usable even if processing fails
    }
  }

  /// Add __brick__ to the cloned repository.
  /// 
  /// This method creates a __brick__ directory structure beside each widget
  /// with brick.yaml metadata files and copies the widget files.
  /// 
  /// [repositoryPath] - The path to the cloned repository
  /// [config] - The fpx configuration object
  Future<void> _addBricksToRepository(String repositoryPath, FpxConfig config) async {
    try {
      // Find all available widgets in the configured bricks path
      final availableWidgets = await _findAvailableWidgets(repositoryPath, config);
      
      _logger.info('🔍 Found ${availableWidgets.length} widget(s):');
      
      for (final widget in availableWidgets) {
        _logger.info('  • ${widget.name} (${widget.files.length} file(s))');
        
        // Create __brick__ directory beside the widget
        final widgetBricksDir = Directory(path.join(widget.path, '__brick__'));
        
        // Skip if __brick__ directory already exists (already processed)
        if (await widgetBricksDir.exists()) {
          _logger.detail('    Skipping ${widget.name} - already has __brick__ directory');
          continue;
        }
        
        await widgetBricksDir.create(recursive: true);
        
        // Create brick.yaml file
        await _createBrickYaml(repositoryPath, widget.path, widget.name);
        
        // Copy widget files into __brick__ folder
        await _copyWidgetFiles(widget, widgetBricksDir.path);
        
        // Preprocess widget files to replace foundation constants with actual values
        await _preprocessWidgetFiles(repositoryPath, widgetBricksDir.path, config);
        
        _logger.detail('    Created __brick__ for ${widget.name}');
      }
      
      _logger.success('✅ Created __brick__ structures for all widgets');
    } catch (e) {
      _logger.warn('Failed to process widgets: $e'); // coverage:ignore-line
      rethrow; // coverage:ignore-line
    }
  }

  /// Find all available widgets in the configured bricks path.
  /// 
  /// This method scans the bricks directory to identify widget folders
  /// and their associated files.
  /// 
  /// [repositoryPath] - The path to the cloned repository
  /// [config] - The fpx configuration object
  /// 
  /// Returns a list of [WidgetInfo] objects representing found widgets.
  Future<List<WidgetInfo>> _findAvailableWidgets(String repositoryPath, FpxConfig config) async {
    final bricksPath = path.join(repositoryPath, config.bricks.path);
    final bricksDir = Directory(bricksPath);
    
    if (!await bricksDir.exists()) {
      _logger.warn('Bricks directory not found: ${bricksDir.path}'); // coverage:ignore-line
      return []; // coverage:ignore-line
    }
    
    final widgets = <WidgetInfo>[];
    
    try {
      // List all directories in the bricks path
      final entities = await bricksDir.list(followLinks: false).toList();
      
      for (final entity in entities) {
        if (entity is Directory) {
          final widgetName = path.basename(entity.path);
          
          // Skip __brick__ directories (they are not components)
          if (widgetName == '__brick__') {
            continue;
          }
          
          final widgetFiles = await _getWidgetFiles(entity.path);
          
          if (widgetFiles.isNotEmpty) {
            widgets.add(WidgetInfo(
              name: widgetName,
              path: entity.path,
              files: widgetFiles,
            ));
          }
        }
      }
      
      // Sort widgets by name for consistent output
      widgets.sort((a, b) => a.name.compareTo(b.name));
      
    } catch (e) {
      _logger.warn('Error scanning widgets directory: $e'); // coverage:ignore-line
    }
    
    return widgets;
  }

  /// Get all Dart files in a widget directory.
  /// 
  /// [widgetPath] - The path to the widget directory
  /// 
  /// Returns a list of relative file paths within the widget directory.
  Future<List<String>> _getWidgetFiles(String widgetPath) async {
    final widgetDir = Directory(widgetPath);
    final files = <String>[];
    
    try {
      final entities = await widgetDir.list(recursive: true, followLinks: false).toList();
      
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Get relative path from widget directory
          final relativePath = path.relative(entity.path, from: widgetPath);
          
          // Skip files inside __brick__ directories
          if (!relativePath.contains('__brick__')) {
            files.add(relativePath);
          }
        }
      }
      
      // Sort files for consistent output
      files.sort();
    } catch (e) {
      _logger.warn('Error reading widget files in $widgetPath: $e'); // coverage:ignore-line
    }
    
    return files;
  }

  /// Create a brick.yaml file for a widget.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [widgetPath] - The path to the widget directory
  /// [widgetName] - The name of the widget
  Future<void> _createBrickYaml(String repositoryPath, String widgetPath, String widgetName) async {
    final brickYamlFile = File(path.join(widgetPath, 'brick.yaml'));
    
    // Read version from repository's pubspec.yaml
    final version = await _getRepositoryVersion(repositoryPath);
    
    final brickYamlContent = '''name: $widgetName
description: A $widgetName widget component
version: $version

vars:
  name:
    type: string
    description: The name for this component
    default: $widgetName
    prompt: What is the name of this component?
''';

    await brickYamlFile.writeAsString(brickYamlContent);
    _logger.detail('Created brick.yaml for $widgetName');
  }

  /// Get the version from the repository's pubspec.yaml file.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// 
  /// Returns the version string from pubspec.yaml, or a default version if not found.
  Future<String> _getRepositoryVersion(String repositoryPath) async {
    final pubspecFile = File(path.join(repositoryPath, 'pubspec.yaml'));
    
    if (!await pubspecFile.exists()) {
      _logger.warn('pubspec.yaml not found, using default version'); // coverage:ignore-line
      return '0.1.0+1'; // coverage:ignore-line
    }
    
    try {
      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('version:')) {
          final version = trimmedLine.substring(8).trim();
          _logger.detail('Found repository version: $version');
          return version;
        }
      }
      
      _logger.warn('Version not found in pubspec.yaml, using default'); // coverage:ignore-line
      return '0.1.0+1'; // coverage:ignore-line
    } catch (e) {
      _logger.warn('Error reading pubspec.yaml: $e, using default version'); // coverage:ignore-line
      return '0.1.0+1'; // coverage:ignore-line
    }
  }

  /// Copy widget files into the __brick__ directory.
  /// 
  /// [widget] - The widget information object
  /// [bricksPath] - The path to the __brick__ directory
  Future<void> _copyWidgetFiles(WidgetInfo widget, String bricksPath) async {
    final dartFiles = widget.files.where((f) => f.endsWith('.dart')).toList();
    final nonDartFiles = widget.files.where((f) => !f.endsWith('.dart')).toList();
    
    // Copy non-Dart files as-is
    for (final file in nonDartFiles) {
      final sourceFile = File(path.join(widget.path, file));
      final targetFile = File(path.join(bricksPath, file));
      
      // Ensure target directory exists
      await targetFile.parent.create(recursive: true);
      
      // Copy the file
      await sourceFile.copy(targetFile.path);
      _logger.detail('    Copied $file to __brick__');
    }
    
    // Handle Dart files
    if (dartFiles.isEmpty) {
      return;
    } else if (dartFiles.length == 1) {
      // Single Dart file - copy as-is
      final file = dartFiles.first;
      final sourceFile = File(path.join(widget.path, file));
      final targetFile = File(path.join(bricksPath, file));
      
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetFile.path);
      _logger.detail('    Copied $file to __brick__');
    } else {
      // Multiple Dart files - check if they are in nested directories
      final hasNestedFiles = dartFiles.any((file) => file.contains('/') || file.contains('\\'));
      
      if (hasNestedFiles) {
        // Files are in nested directories - copy preserving structure
        for (final file in dartFiles) {
          final sourceFile = File(path.join(widget.path, file));
          final targetFile = File(path.join(bricksPath, file));
          
          await targetFile.parent.create(recursive: true);
          await sourceFile.copy(targetFile.path);
          _logger.detail('    Copied $file to __brick__');
        }
      } else {
        // Multiple files in same directory - merge into a single file
        await _mergeDartFiles(widget, dartFiles, bricksPath);
      }
    }
  }

  /// Merge multiple Dart files into a single file to avoid import issues.
  /// 
  /// This method combines all Dart files in a component into a single file,
  /// removing duplicate imports and preserving all class definitions.
  /// 
  /// [widget] - The widget information object
  /// [dartFiles] - List of Dart file names to merge
  /// [bricksPath] - The path to the __brick__ directory
  Future<void> _mergeDartFiles(WidgetInfo widget, List<String> dartFiles, String bricksPath) async {
    final imports = <String>{};
    final contents = <String>[];
    String? primaryFileName;
    
    // Sort files to process the main component file first
    dartFiles.sort((a, b) {
      // Prioritize files that contain the component name (e.g., base_input.dart for input component)
      final aContainsName = a.toLowerCase().contains(widget.name.toLowerCase());
      final bContainsName = b.toLowerCase().contains(widget.name.toLowerCase());
      
      if (aContainsName && !bContainsName) return -1;
      if (!aContainsName && bContainsName) return 1;
      return a.compareTo(b);
    });
    
    primaryFileName = dartFiles.first;
    
    for (final file in dartFiles) {
      final sourceFile = File(path.join(widget.path, file));
      final content = await sourceFile.readAsString();
      
      // Extract imports and content separately
      final lines = content.split('\n');
      final fileImports = <String>[];
      final fileContent = <String>[];
      bool inImports = true;
      
      for (final line in lines) {
        final trimmedLine = line.trim();
        
        if (inImports && (trimmedLine.startsWith('import ') || trimmedLine.startsWith('export '))) {
          // Skip relative imports between component files
          if (!trimmedLine.contains('./') && !trimmedLine.contains('../')) {
            fileImports.add(line);
            imports.add(trimmedLine);
          }
        } else {
          if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('//') && !trimmedLine.startsWith('import ') && !trimmedLine.startsWith('export ')) {
            inImports = false;
          }
          
          if (!inImports) {
            fileContent.add(line);
          }
        }
      }
      
      if (fileContent.isNotEmpty) {
        contents.add('// === Content from $file ===');
        contents.addAll(fileContent);
        contents.add('');
      }
      
      _logger.detail('    Processed $file for merging');
    }
    
    // Create the merged file
    final mergedContent = StringBuffer();
    
    // Add all unique imports first
    final sortedImports = imports.toList()..sort();
    for (final import in sortedImports) {
      mergedContent.writeln(import);
    }
    
    if (sortedImports.isNotEmpty) {
      mergedContent.writeln();
    }
    
    // Add all content
    for (final content in contents) {
      mergedContent.writeln(content);
    }
    
    // Write to the primary file name
    final targetFile = File(path.join(bricksPath, primaryFileName!));
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString(mergedContent.toString());
    
    _logger.detail('    Merged ${dartFiles.length} Dart files into $primaryFileName');
  }

  /// Preprocess widget files to replace foundation constants with actual values.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [bricksPath] - The path to the __brick__ directory containing copied files
  /// [config] - The fpx configuration object
  Future<void> _preprocessWidgetFiles(String repositoryPath, String bricksPath, FpxConfig config) async {
    _logger.detail('🔧 Preprocessing widget files...');
    
    // Parse foundation files to extract constants
    final foundationConstants = await _parseFoundationFiles(repositoryPath, config);
    
    if (foundationConstants.isEmpty) {
      _logger.warn('No foundation constants found to replace'); // coverage:ignore-line
      return; // coverage:ignore-line
    }
    
    _logger.detail('Found ${foundationConstants.length} foundation constants');
    
    // Get foundation file paths for import removal
    final foundationPaths = config.variables.foundation.paths;
    
    // Track third-party dependencies across all files
    final thirdPartyDependencies = <String>{};
    
    // Process all Dart files in the __brick__ directory
    final bricksDir = Directory(bricksPath);
    final dartFiles = await bricksDir
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .cast<File>()
        .toList();
    
    for (final file in dartFiles) {
      await _replaceFoundationConstants(file, foundationConstants, foundationPaths, thirdPartyDependencies);
    }
    
    // Create README.md if there are third-party dependencies
    if (thirdPartyDependencies.isNotEmpty) {
      await _createDependenciesReadme(bricksPath, thirdPartyDependencies); // coverage:ignore-line
    }
    
    _logger.detail('✅ Preprocessing completed');
  }

  /// Parse foundation files to extract constant definitions.
  /// 
  /// [repositoryPath] - The path to the repository root
  /// [config] - The fpx configuration object
  /// 
  /// Returns a map of constant names to their values.
  Future<Map<String, String>> _parseFoundationFiles(String repositoryPath, FpxConfig config) async {
    final constants = <String, String>{};
    
    try {
      // Parse all foundation files dynamically
      for (final entry in config.variables.foundation.entries) {
        final foundationKey = entry.key;
        final foundationItem = entry.value;
        final foundationFile = File(path.join(repositoryPath, foundationItem.path));
        
        if (await foundationFile.exists()) {
          final className = await _extractClassName(foundationFile);
          if (className != null) {
            final foundationConstants = await _parseConstantsFromFile(foundationFile, className);
            constants.addAll(foundationConstants);
            _logger.detail('Processed $foundationKey: ${foundationConstants.length} constants from $className');
          }
        } else {
          _logger.warn('Foundation file not found: ${foundationItem.path}'); // coverage:ignore-line
        }
      }
    } catch (e) {
      _logger.warn('Error parsing foundation files: $e'); // coverage:ignore-line
    }
    
    return constants;
  }

  /// Extract the main class name from a foundation file.
  /// 
  /// [file] - The foundation file to analyze
  /// 
  /// Returns the class name if found, null otherwise.
  Future<String?> _extractClassName(File file) async {
    try {
      final content = await file.readAsString();
      
      // Look for class declarations - handle various patterns
      final classPatterns = [
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{'),           // class ClassName {
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends'),      // class ClassName extends
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+implements'),   // class ClassName implements
        RegExp(r'class\s+([A-Za-z_][A-Za-z0-9_]*)\s+with'),         // class ClassName with
      ];
      
      for (final pattern in classPatterns) {
        final match = pattern.firstMatch(content);
        if (match != null) {
          final className = match.group(1)!;
          _logger.detail('Found class: $className in ${path.basename(file.path)}');
          return className;
        }
      }
      
      _logger.warn('No class found in ${path.basename(file.path)}'); // coverage:ignore-line
      return null; // coverage:ignore-line
    } catch (e) {
      _logger.warn('Error extracting class name from ${file.path}: $e'); // coverage:ignore-line
      return null; // coverage:ignore-line
    }
  }

  /// Parse constants from a single foundation file using Dart analyzer.
  /// 
  /// [file] - The foundation file to parse
  /// [className] - The name of the class containing constants
  /// 
  /// Returns a map of constant names to their values with const prefix when needed.
  Future<Map<String, String>> _parseConstantsFromFile(File file, String className) async {
    final constants = <String, String>{};
    
    try {
      // First try using the Dart analyzer for proper constant resolution
      final analyzerConstants = await _parseConstantsWithAnalyzer(file, className);
      if (analyzerConstants.isNotEmpty) {
        return analyzerConstants;
      }
      
      // Fallback to regex parsing if analyzer fails
      final regexConstants = await _parseConstantsWithRegex(file, className);
      return regexConstants;
    } catch (e) {
      return constants;
    }
  }

  /// Parse constants using the Dart analyzer for accurate resolution.
  /// 
  /// [file] - The foundation file to parse
  /// [className] - The name of the class containing constants
  /// 
  /// Returns a map of constant names to their resolved values.
  Future<Map<String, String>> _parseConstantsWithAnalyzer(File file, String className) async {
    final constants = <String, String>{};
    
    try {
      // Create analysis context for the file
      final collection = AnalysisContextCollection(
        includedPaths: [file.parent.path],
        resourceProvider: PhysicalResourceProvider.INSTANCE,
      );
      
      final context = collection.contextFor(file.path);
      final result = await context.currentSession.getResolvedUnit(file.path);
      
      if (result is ResolvedUnitResult) {
        final unit = result.unit;
        
        // Find the class declaration
        for (final declaration in unit.declarations) {
          if (declaration is ClassDeclaration && declaration.name.lexeme == className) {
            // Find all static const/final fields
            for (final member in declaration.members) {
              if (member is FieldDeclaration && member.isStatic && (member.fields.isConst || member.fields.isFinal)) {
                for (final variable in member.fields.variables) {
                  final fieldName = variable.name.lexeme;
                  final initializer = variable.initializer;
                  
                  if (initializer != null) {
                    // Try to evaluate the constant expression
                    final constantValue = _evaluateConstantExpression(initializer, result.libraryElement);
                    
                    if (constantValue != null) {
                      final fullName = '$className.$fieldName';
                      constants[fullName] = constantValue;
                      _logger.info('Analyzer resolved: $fullName = $constantValue');
                    }
                  }
                }
              }
            }
            break;
          }
        }
      }
    } catch (e) {
      _logger.detail('Analyzer parsing failed for ${file.path}: $e');
    }
    
    return constants;
  }

  /// Evaluate a constant expression to its string representation.
  /// 
  /// [expression] - The AST expression to evaluate
  /// [library] - The library element for context
  /// 
  /// Returns the evaluated constant as a string, or null if evaluation fails.
  String? _evaluateConstantExpression(Expression expression, LibraryElement library) {
    try {
      // Handle different types of constant expressions
      if (expression is IntegerLiteral) {
        return expression.value.toString();
      }
      
      if (expression is DoubleLiteral) {
        return expression.value.toString();
      }
      
      if (expression is BooleanLiteral) {
        return expression.value.toString();
      }
      
      if (expression is StringLiteral) {
        return expression.stringValue;
      }
      
      if (expression is SimpleIdentifier) {
        // Try to resolve identifier references
        final element = expression.staticElement;
        if (element is FieldElement && element.isStatic && element.isConst) {
          final constantValue = element.computeConstantValue();
          if (constantValue != null && constantValue.hasKnownValue) {
            // Handle different types of constant values
            if (constantValue.toDoubleValue() != null) {
              return constantValue.toDoubleValue().toString();
            }
            if (constantValue.toIntValue() != null) {
              return constantValue.toIntValue().toString();
            }
            if (constantValue.toBoolValue() != null) {
              return constantValue.toBoolValue().toString();
            }
            if (constantValue.toStringValue() != null) {
              return '"${constantValue.toStringValue()}"';
            }
          }
        }
      }
      
      if (expression is InstanceCreationExpression) {
        // Handle constructor calls like EdgeInsets.only(right: 8.0), Color(0xFF123456)
        final constructorName = expression.constructorName.toString();
        final arguments = expression.argumentList.arguments;
        
        // Build the constructor call string with resolved arguments
        final resolvedArgs = <String>[];
        for (final arg in arguments) {
          if (arg is NamedExpression) {
            final argName = arg.name.label.name;
            final argValue = _evaluateConstantExpression(arg.expression, library);
            if (argValue != null) {
              resolvedArgs.add('$argName: $argValue');
            } else {
              return null; // Can't resolve all arguments
            }
          } else {
            final argValue = _evaluateConstantExpression(arg, library);
            if (argValue != null) {
              resolvedArgs.add(argValue);
            } else {
              return null; // Can't resolve all arguments
            }
          }
        }
        
        return 'const $constructorName(${resolvedArgs.join(', ')})';
      }
      
      if (expression is MethodInvocation) {
        // Handle method calls like BorderRadius.circular(8.0)
        final target = expression.target?.toString() ?? '';
        final methodName = expression.methodName.name;
        final arguments = expression.argumentList.arguments;
        
        final resolvedArgs = <String>[];
        for (final arg in arguments) {
          final argValue = _evaluateConstantExpression(arg, library);
          if (argValue != null) {
            resolvedArgs.add(argValue);
          } else {
            return null;
          }
        }
        
        final fullMethodName = target.isNotEmpty ? '$target.$methodName' : methodName;
        return 'const $fullMethodName(${resolvedArgs.join(', ')})';
      }
      
      // For property access like FontWeight.w400, UiColors.primary
      if (expression is PropertyAccess) {
        return expression.toString();
      }
      
      // For prefixed identifiers like UiSpacing.xs
      if (expression is PrefixedIdentifier) {
        return expression.toString();
      }
      
    } catch (e) {
      _logger.detail('Failed to evaluate expression: $e');
    }
    
    return null;
  }

  /// Convert a DartObject string representation to a clean format.
  String _dartObjectToString(String objectString) {
    // Clean up the DartObject string representation
    // This is a simple cleanup - in practice you might need more sophisticated parsing
    return objectString.replaceAll('DartObject(', '').replaceAll(')', '');
  }

  /// Parse constants using regex as a fallback method.
  /// 
  /// [file] - The foundation file to parse
  /// [className] - The name of the class containing constants
  /// 
  /// Returns a map of constant names to their values with const prefix when needed.
  Future<Map<String, String>> _parseConstantsWithRegex(File file, String className) async {
    final constants = <String, String>{};
    final rawConstants = <String, String>{}; // Store raw values for reference resolution
    
    try {
      final content = await file.readAsString();
      
      // More comprehensive regex to match all static const and static final declarations
      // Matches: static const/final [Type] [name] = [value];
      // Handles multi-word types, numbers, underscores in names, and multiline values
      // Now captures the declaration type (const or final)
      final constRegex = RegExp(
        r'static\s+(const|final)\s+(\w+(?:\<[\w\s,<>]+\>)?)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*([^;]+);',
        multiLine: true,
        dotAll: true,
      );
      
      final matches = constRegex.allMatches(content);
      
      // First pass: collect all raw constant definitions
      for (final match in matches) {
        final constantName = match.group(3)!.trim();
        final constantValue = match.group(4)!.trim();
        
        // Clean up the value - remove extra whitespace and newlines
        final cleanValue = constantValue.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        rawConstants[constantName] = cleanValue;
      }
      
      // Second pass: resolve references and process values
      for (final match in matches) {
        final declarationType = match.group(1)!.trim(); // 'const' or 'final'
        final constantType = match.group(2)!.trim(); // Type like TextStyle, Color, etc.
        final constantName = match.group(3)!.trim();
        final constantValue = match.group(4)!.trim();
        
        // Clean up the value - remove extra whitespace and newlines
        final cleanValue = constantValue.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        // Resolve constant references within the same class
        final resolvedValue = _resolveConstantReferences(cleanValue, rawConstants);
        
        // Check if this is a complex object that should be handled specially
        final replacementValue = _processConstantValue(
          declarationType, 
          constantType, 
          constantName, 
          resolvedValue,
        );
        
        if (replacementValue != null) {
          // Store with full class prefix for replacement
          constants['$className.$constantName'] = replacementValue;
          _logger.info('Found $declarationType: $className.$constantName = $replacementValue');
        } else {
          _logger.warn('Skipped complex constant: $className.$constantName (requires manual handling)'); // coverage:ignore-line
        }
      }
      
      _logger.detail('Parsed ${constants.length} constants from $className'); // coverage:ignore-line
    } catch (e) {
      _logger.warn('Error parsing constants from ${file.path}: $e'); // coverage:ignore-line
    }
    
    return constants;
  }

  /// Resolve constant references within the same class.
  /// 
  /// [value] - The constant value that may contain references
  /// [rawConstants] - Map of constant names to their raw values within the same class
  /// 
  /// Returns the resolved value with references replaced by actual values.
  String _resolveConstantReferences(String value, Map<String, String> rawConstants) {
    String resolvedValue = value;
    
    // Keep resolving until no more references are found (handles chains like xs -> spacing2 -> 8.0)
    bool hasChanges = true;
    int maxIterations = 15; // Prevent infinite loops
    int iterations = 0;
    
    while (hasChanges && iterations < maxIterations) {
      hasChanges = false;
      iterations++;
      
      // Look for identifier references and replace them with their resolved values
      for (final entry in rawConstants.entries) {
        final constantName = entry.key;
        final constantValue = entry.value;
        
        // Check if the value is exactly the constant name (simple reference)
        if (resolvedValue.trim() == constantName) {
          final recursivelyResolved = _resolveConstantReferences(constantValue, rawConstants);
          resolvedValue = recursivelyResolved;
          hasChanges = true;
          break; // Start over with the new value
        }
        
        // Check for the constant name used within expressions (e.g., "EdgeInsets.only(right: xs)")
        // Use word boundaries to ensure we don't replace partial matches
        final constantRegex = RegExp(r'\b' + RegExp.escape(constantName) + r'\b');
        if (constantRegex.hasMatch(resolvedValue)) {
          // Recursively resolve the referenced constant first
          final referencedValue = _resolveConstantReferences(constantValue, rawConstants);
          
          // Replace the constant name with its resolved value
          final newResolvedValue = resolvedValue.replaceAll(constantRegex, referencedValue);
          
          if (newResolvedValue != resolvedValue) {
            resolvedValue = newResolvedValue;
            hasChanges = true;
            break; // Start over with the new value
          }
        }
      }
    }
    
    return resolvedValue;
  }

  /// Process a constant value to determine the best replacement strategy.
  /// 
  /// [declarationType] - Whether the constant was declared as 'const' or 'final'
  /// [constantType] - The type of the constant (e.g., 'TextStyle', 'Color', etc.)
  /// [constantName] - The name of the constant
  /// [constantValue] - The raw value string from the source code
  /// 
  /// Returns the processed replacement value, or null if the constant should be skipped.
  String? _processConstantValue(
    String declarationType, 
    String constantType, 
    String constantName, 
    String constantValue,
  ) {
    // Handle simple primitive types and direct constructors
    if (_isSimpleConstant(constantType, constantValue)) {
      // For primitive values, never add const keyword
      if (_isPrimitiveValue(constantValue)) {
        return constantValue;
      }
      
      // For constructor calls and complex objects, preserve const if original was const
      if (_needsConstKeyword(constantValue)) {
        return declarationType == 'const' ? 'const $constantValue' : constantValue;
      }
      
      // For simple references (like FontWeight.w400), don't add const
      return constantValue;
    }

    // Handle TextStyle specifically - convert complex TextStyle to simpler equivalent
    if (constantType == 'TextStyle' && _isComplexTextStyle(constantValue)) {
      final simpleTextStyle = _convertToSimpleTextStyle(constantValue);
      if (simpleTextStyle != null) {
        return declarationType == 'const' ? 'const $simpleTextStyle' : simpleTextStyle;
      }
    }

    // Handle Color types - try to extract simple color values
    if (constantType == 'Color' && _isComplexColor(constantValue)) {
      final simpleColor = _convertToSimpleColor(constantValue);
      if (simpleColor != null) {
        return declarationType == 'const' ? 'const $simpleColor' : simpleColor;
      }
    }

    // For other complex objects, skip replacement and let user handle manually
    _logger.warn('Skipping complex $constantType constant: $constantName'); // coverage:ignore-line
    return null; // coverage:ignore-line
  }

  /// Check if a value is a primitive type that doesn't need const keyword.
  bool _isPrimitiveValue(String constantValue) {
    final trimmedValue = constantValue.trim();
    
    final primitivePatterns = [
      RegExp(r'^\d+$'), // Plain integers: 42
      RegExp(r'^\d+\.\d+$'), // Plain decimals: 4.0, 8.5
      RegExp(r'^true|false$'), // Booleans: true, false
      RegExp(r'^"[^"]*"$'), // String literals: "hello"
      RegExp(r"^'[^']*'$"), // String literals: 'hello'
      RegExp(r'^null$'), // null value
    ];
    
    return primitivePatterns.any((pattern) => pattern.hasMatch(trimmedValue));
  }

  /// Check if a value needs the const keyword (constructor calls, etc.).
  bool _needsConstKeyword(String constantValue) {
    final trimmedValue = constantValue.trim();
    
    final constRequiredPatterns = [
      RegExp(r'^\w+\('), // Constructor calls: Color(0xFF123456), EdgeInsets.all(8)
      RegExp(r'^\w+\.\w+\('), // Named constructor calls: EdgeInsets.symmetric(...)
    ];
    
    return constRequiredPatterns.any((pattern) => pattern.hasMatch(trimmedValue));
  }

  /// Check if a constant value is simple enough to be replaced directly.
  bool _isSimpleConstant(String constantType, String constantValue) {
    // Handle primitive types and simple constructors
    final simplePatterns = [
      RegExp(r'^\d+$'), // Plain numbers
      RegExp(r'^\d+\.\d+$'), // Decimal numbers
      RegExp(r'^true|false$'), // Booleans
      RegExp(r'^"[^"]*"$'), // String literals
      RegExp(r"^'[^']*'$"), // String literals with single quotes
      RegExp(r'^FontWeight\.w\d+$'), // FontWeight constants
      RegExp(r'^EdgeInsets\.(all|symmetric|only)\([^)]+\)$'), // Simple EdgeInsets
      RegExp(r'^BorderRadius\.(all|circular)\([^)]+\)$'), // Simple BorderRadius
      RegExp(r'^Duration\([^)]+\)$'), // Duration constructors
      RegExp(r'^Color\(0x[A-Fa-f0-9]{8}\)$'), // Simple Color constructors
      RegExp(r'^SizedBox\([^)]+\)$'), // SizedBox constructors
    ];

    return simplePatterns.any((pattern) => pattern.hasMatch(constantValue.trim()));
  }

  /// Check if a TextStyle uses complex external functions.
  bool _isComplexTextStyle(String constantValue) {
    return constantValue.contains('GoogleFonts.') || 
           constantValue.contains('_outfitTextStyle') ||
           constantValue.contains('_') || // Any private method call
           constantValue.contains('Theme.of(') ||
           constantValue.contains('context.');
  }

  /// Convert a complex TextStyle to a simpler equivalent.
  String? _convertToSimpleTextStyle(String constantValue) {
    try {
      // Extract basic properties from GoogleFonts or custom TextStyle calls
      final Map<String, String> properties = {};
      
      // Look for fontSize: pattern
      final fontSizeMatch = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (fontSizeMatch != null) {
        properties['fontSize'] = fontSizeMatch.group(1)!;
      }
      
      // Look for fontWeight: pattern
      final fontWeightMatch = RegExp(r'fontWeight:\s*(FontWeight\.\w+|\w+)').firstMatch(constantValue);
      if (fontWeightMatch != null) {
        var weight = fontWeightMatch.group(1)!;
        // Convert simple references to FontWeight constants
        if (!weight.startsWith('FontWeight.')) {
          // Map common weight names to FontWeight constants
          switch (weight) {
            case 'regular': weight = 'FontWeight.w400'; break;
            case 'medium': weight = 'FontWeight.w500'; break;
            case 'semiBold': weight = 'FontWeight.w600'; break;
            case 'bold': weight = 'FontWeight.w700'; break;
            default: weight = 'FontWeight.w400'; break;
          }
        }
        properties['fontWeight'] = weight;
      }
      
      // Look for height: pattern (line height ratio)
      final heightMatch = RegExp(r'height:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (heightMatch != null) {
        properties['height'] = heightMatch.group(1)!;
      }
      
      // Look for letterSpacing: pattern
      final letterSpacingMatch = RegExp(r'letterSpacing:\s*(\d+(?:\.\d+)?)').firstMatch(constantValue);
      if (letterSpacingMatch != null) {
        properties['letterSpacing'] = letterSpacingMatch.group(1)!;
      }
      
      // Look for decoration: pattern
      final decorationMatch = RegExp(r'decoration:\s*(TextDecoration\.\w+)').firstMatch(constantValue);
      if (decorationMatch != null) {
        properties['decoration'] = decorationMatch.group(1)!;
      }
      
      // Build a simple TextStyle constructor
      if (properties.isNotEmpty) {
        final propertyStrings = properties.entries.map((e) => '${e.key}: ${e.value}').toList(); // coverage:ignore-line
        return 'TextStyle(${propertyStrings.join(', ')})'; // coverage:ignore-line
      }
    } catch (e) {
      _logger.warn('Failed to convert TextStyle: $e'); // coverage:ignore-line
    }
    
    return null; // coverage:ignore-line
  }

  /// Check if a Color uses complex external functions.
  bool _isComplexColor(String constantValue) {
    return constantValue.contains('Color.fromRGBO') ||
           constantValue.contains('Color.fromARGB') ||
           constantValue.contains('HSLColor.') ||
           constantValue.contains('HSVColor.') ||
           constantValue.contains('Theme.of(') ||
           constantValue.contains('context.');
  }

  /// Convert a complex Color to a simpler equivalent.
  String? _convertToSimpleColor(String constantValue) {
    try {
      // Handle Color.fromRGBO(r, g, b, opacity)
      final rgboMatch = RegExp(r'Color\.fromRGBO\((\d+),\s*(\d+),\s*(\d+),\s*([0-9.]+)\)').firstMatch(constantValue);
      if (rgboMatch != null) {
        final r = int.parse(rgboMatch.group(1)!);
        final g = int.parse(rgboMatch.group(2)!);
        final b = int.parse(rgboMatch.group(3)!);
        final opacity = double.parse(rgboMatch.group(4)!);
        
        // Convert to hex if opacity is 1.0, otherwise keep RGBA
        if (opacity == 1.0) {
          final hex = ((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0').toUpperCase(); // coverage:ignore-line
          return 'Color(0xFF$hex)'; // coverage:ignore-line
        } else {
          final alpha = (opacity * 255).round(); // coverage:ignore-line
          final hex = ((alpha << 24) | (r << 16) | (g << 8) | b).toRadixString(16).padLeft(8, '0').toUpperCase(); // coverage:ignore-line
          return 'Color(0x$hex)'; // coverage:ignore-line
        }
      }
      
      // Handle Color.fromARGB(a, r, g, b)
      final argbMatch = RegExp(r'Color\.fromARGB\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)').firstMatch(constantValue);
      if (argbMatch != null) {
        final a = int.parse(argbMatch.group(1)!); // coverage:ignore-line
        final r = int.parse(argbMatch.group(2)!); // coverage:ignore-line
        final g = int.parse(argbMatch.group(3)!); // coverage:ignore-line
        final b = int.parse(argbMatch.group(4)!); // coverage:ignore-line
        
        final hex = ((a << 24) | (r << 16) | (g << 8) | b).toRadixString(16).padLeft(8, '0').toUpperCase(); // coverage:ignore-line
        return 'Color(0x$hex)'; // coverage:ignore-line
      }
    } catch (e) {
      _logger.warn('Failed to convert Color: $e'); // coverage:ignore-line
    }
    
    return null; // coverage:ignore-line
  }

  /// Replace foundation constants in a widget file with their actual values.
  /// 
  /// [file] - The widget file to process
  /// [constants] - Map of constant names to their values
  /// [foundationPaths] - List of foundation file paths for import removal
  /// [thirdPartyDependencies] - Set to collect third-party dependencies found
  Future<void> _replaceFoundationConstants(
    File file, 
    Map<String, String> constants, 
    List<String> foundationPaths,
    Set<String> thirdPartyDependencies,
  ) async {
    try {
      String content = await file.readAsString();
      bool wasModified = false;
      
      // Sort constants by length (longest first) to avoid partial replacements
      final sortedConstants = constants.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      
      // Replace each constant with its value using word boundaries
      for (final entry in sortedConstants) {
        final constantName = entry.key;
        final constantValue = entry.value;
        
        // Use word boundary regex to ensure we're replacing complete identifiers
        final escapedConstantName = RegExp.escape(constantName);
        final constantRegex = RegExp(r'\b' + escapedConstantName + r'\b');
        
        if (constantRegex.hasMatch(content)) {
          content = content.replaceAll(constantRegex, constantValue); // coverage:ignore-line
          wasModified = true; // coverage:ignore-line
          _logger.detail('    Replaced $constantName with $constantValue'); // coverage:ignore-line
        }
      }
      
      // Remove foundation imports and collect third-party dependencies
      if (wasModified) {
        content = _removeFoundationImports(content, foundationPaths, thirdPartyDependencies); // coverage:ignore-line
        await file.writeAsString(content); // coverage:ignore-line
        _logger.detail('    Preprocessed ${path.basename(file.path)}'); // coverage:ignore-line
      }
    } catch (e) {
      _logger.warn('Error processing ${file.path}: $e'); // coverage:ignore-line
    }
  }

  /// Remove import statements that reference foundation files.
  /// 
  /// [content] - The file content to process
  /// [foundationPaths] - List of foundation file paths to match against
  /// [thirdPartyDependencies] - Set to collect third-party dependencies found
  /// 
  /// Returns the content with foundation imports removed.
  String _removeFoundationImports(String content, List<String> foundationPaths, Set<String> thirdPartyDependencies) {
    final lines = content.split('\n');
    final filteredLines = <String>[];
    
    // Extract just the filenames from foundation paths for matching
    final foundationFileNames = foundationPaths
        .map((p) => path.basename(p))
        .toSet();
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.startsWith('import ')) {
        bool shouldRemove = false;
        
        // PRESERVE Flutter, Dart, and other standard imports
        if (_isStandardImport(trimmedLine)) {
          _logger.detail('    Preserved standard import: $trimmedLine'); // coverage:ignore-line
          filteredLines.add(line); // coverage:ignore-line
          continue; // coverage:ignore-line
        }
        
        // Check if import contains any specific foundation file names
        for (final fileName in foundationFileNames) {
          if (trimmedLine.contains(fileName)) {
            shouldRemove = true; // coverage:ignore-line
            break; // coverage:ignore-line
          }
        }
        
        // Check for foundation directory patterns
        if (!shouldRemove && (
            trimmedLine.contains('/foundation/') || 
            trimmedLine.contains('/src/foundation/'))) {
          shouldRemove = true; // coverage:ignore-line
        }
        
        // Check if it's a main package import (like the entire design system)
        if (!shouldRemove && _isMainPackageImport(trimmedLine, foundationPaths)) {
          shouldRemove = true; // coverage:ignore-line
        }
        
        if (shouldRemove) {
          _logger.detail('    Removed import: $trimmedLine'); // coverage:ignore-line
          continue; // coverage:ignore-line
        }
        
        // If we reach here, it's a third-party import that should be kept
        // but we need to track it for the README
        if (trimmedLine.contains('package:') && !_isStandardImport(trimmedLine)) {
          final packageMatch = RegExp(r'package:([^/\s]+)').firstMatch(trimmedLine);
          if (packageMatch != null) {
            final packageName = packageMatch.group(1)!; // coverage:ignore-line
            thirdPartyDependencies.add(packageName); // coverage:ignore-line
            _logger.detail('    Tracked third-party dependency: $packageName'); // coverage:ignore-line
          }
        }
      }
      
      filteredLines.add(line);
    }
    
    return filteredLines.join('\n');
  }

  /// Check if an import is a standard Flutter/Dart import that should be preserved.
  bool _isStandardImport(String importLine) {
    return importLine.contains('dart:') ||
           importLine.contains('package:flutter/') ||
           importLine.contains('package:material/') ||
           importLine.contains('package:cupertino/') ||
           importLine.contains('package:widgets/') ||
           importLine.contains('package:meta/');
  }

  /// Create a README.md file in the __brick__ directory with dependency information.
  /// 
  /// [bricksPath] - The path to the __brick__ directory
  /// [dependencies] - Set of third-party package names that need to be installed
  Future<void> _createDependenciesReadme(String bricksPath, Set<String> dependencies) async {
    final readmeFile = File(path.join(bricksPath, 'README.md'));
    
    final sortedDependencies = dependencies.toList()..sort();
    final dependencyList = sortedDependencies.map((dep) => '- $dep').join('\n');
    
    final readmeContent = '''# Dependencies

This widget requires the following packages to be installed before use:

$dependencyList

## Installation

Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
${sortedDependencies.map((dep) => '  $dep: ^latest_version').join('\n')}
```

Then run:

```bash
flutter pub get
```

## Note

Please check the latest versions of these packages on [pub.dev](https://pub.dev) and update the version numbers accordingly.
''';

    await readmeFile.writeAsString(readmeContent);
    _logger.info('📄 Created README.md with ${dependencies.length} dependencies'); // coverage:ignore-line
  }

  /// Check if an import is the main package import (entire design system).
  bool _isMainPackageImport(String importLine, List<String> foundationPaths) {
    // If the import is a package import and any foundation path starts with
    // the same base path, it's likely the main package
    if (!importLine.contains('package:')) return false;
    
    // Extract the package name
    final packageMatch = RegExp(r'package:([^/\s]+)').firstMatch(importLine);
    if (packageMatch != null) {
      final packageName = packageMatch.group(1)!;
      
      // Heuristic: if the import is something like package:my_ui/my_ui.dart
      // or just contains the package name as the main barrel file
      if (importLine.contains('$packageName/$packageName.dart') ||
          importLine.contains('$packageName.dart')) {
        _logger.detail('    Identified main package import: $packageName'); // coverage:ignore-line
        return true; // coverage:ignore-line
      }
      
      // Additional check: if foundation paths suggest this is the current project
      // and the import references the same package structure
      for (final foundationPath in foundationPaths) {
        if (foundationPath.contains('lib/') && 
            importLine.contains('package:$packageName/')) {
          // This is likely importing from the same project
          _logger.detail('    Identified project import: $packageName'); // coverage:ignore-line
          return true; // coverage:ignore-line
        }
      }
    }
    
    return false;
  }

  /// Resolve cross-component dependencies in brick templates
  /// 
  /// This method analyzes each brick template for external class references
  /// and includes the corresponding dependency bricks inline.
  Future<void> _resolveBrickDependencies(String repositoryPath, FpxConfig config) async {
    try {
      _logger.info('🔗 Resolving component dependencies...');
      
      final componentsPath = path.join(repositoryPath, config.bricks.path);
      final componentsDir = Directory(componentsPath);
      
      if (!await componentsDir.exists()) {
        _logger.detail('Components directory not found: $componentsPath');
        return;
      }
      
      // Find all components with brick templates
      final components = <String, String>{};
      await for (final entity in componentsDir.list()) {
        if (entity is Directory) {
          final componentName = path.basename(entity.path);
          final brickDir = Directory(path.join(entity.path, '__brick__'));
          if (await brickDir.exists()) {
            components[componentName] = entity.path;
          }
        }
      }
      
      if (components.isEmpty) {
        _logger.detail('No components with brick templates found');
        return;
      }
      
      _logger.info('📦 Found ${components.length} component(s): ${components.keys.join(', ')}');
      
      // Analyze each component for dependencies
      for (final entry in components.entries) {
        final componentName = entry.key;
        final componentPath = entry.value;
        
        await _resolveComponentDependencies(
          componentName, 
          componentPath, 
          components, 
          repositoryPath
        );
      }
      
      _logger.success('✅ Component dependency resolution completed');
    } catch (e, stackTrace) {
      _logger.warn('⚠️  Dependency resolution failed: $e');
      _logger.detail('Stack trace: $stackTrace');
      // Continue without dependencies rather than failing completely
    }
  }

  /// Resolve dependencies for a single component
  Future<void> _resolveComponentDependencies(
    String componentName,
    String componentPath,
    Map<String, String> allComponents,
    String repositoryPath,
  ) async {
    try {
      _logger.detail('🔍 Analyzing dependencies for $componentName...');
      
      final brickDir = Directory(path.join(componentPath, '__brick__'));
      final dependencies = <String>{};
      
      // Analyze all Dart files in the brick template
      await for (final file in brickDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final content = await file.readAsString();
          final detectedClasses = _extractExternalClassReferences(content);
          
          // Find which components provide these classes
          for (final className in detectedClasses) {
            final provider = _findComponentForClass(className, allComponents);
            if (provider != null && provider != componentName) {
              dependencies.add(provider);
            }
          }
        }
      }
      
      if (dependencies.isEmpty) {
        _logger.detail('  No dependencies found for $componentName');
        return;
      }
      
      _logger.info('  📦 $componentName depends on: ${dependencies.join(', ')}');
      
      // Include dependency files in the brick template
      for (final depName in dependencies) {
        await _includeDependencyInBrick(componentName, componentPath, depName, allComponents);
      }

      // Add import statements for dependencies
      await _addImportStatements(componentPath, dependencies);
      
    } catch (e) {
      _logger.warn('  ⚠️  Failed to resolve dependencies for $componentName: $e');
    }
  }

  /// Extract class references that might be external dependencies
  Set<String> _extractExternalClassReferences(String dartCode) {
    final classRefs = <String>{};
    
    // Patterns to find class references
    final patterns = [
      // Constructor calls: SomeClass(...)
      RegExp(r'(?:new\s+)?([A-Z][a-zA-Z0-9]*)\s*\('),
      // Type annotations: SomeClass variable, SomeClass? optional
      RegExp(r':\s*([A-Z][a-zA-Z0-9]*)[<\?\s,\)]'),
      // Static method/property access: SomeClass.method()
      RegExp(r'([A-Z][a-zA-Z0-9]*)\.[a-zA-Z_]'),
      // Enum access: SomeEnum.value
      RegExp(r'([A-Z][a-zA-Z0-9]*)\.[a-z]'),
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(dartCode);
      for (final match in matches) {
        final className = match.group(1);
        if (className != null && _isComponentClass(className)) {
          classRefs.add(className);
        }
      }
    }
    
    return classRefs;
  }

  /// Check if a class name looks like it could be from a component
  bool _isComponentClass(String className) {
    // Skip common Flutter/Dart classes
    final commonClasses = {
      'Widget', 'StatefulWidget', 'StatelessWidget', 'State', 'BuildContext',
      'Key', 'Color', 'TextStyle', 'EdgeInsets', 'BorderRadius', 'Duration',
      'VoidCallback', 'ValueChanged', 'String', 'int', 'double', 'bool', 'List',
      'Map', 'Set', 'Function', 'Object', 'Container', 'Column', 'Row', 'Text',
      'SizedBox', 'Padding', 'Center', 'Align', 'Positioned', 'AnimatedBuilder',
      'GestureDetector', 'InkWell', 'Material', 'Scaffold', 'AppBar', 'Icon',
      'CustomPaint', 'CustomPainter', 'Canvas', 'Size', 'Paint', 'Offset',
      'File', 'Directory', 'LogicalKeyboardKey', 'KeyDownEvent', 'KeyEventResult',
      'MouseRegion', 'Focus', 'Stack', 'SingleTickerProviderStateMixin'
    };
    
    if (commonClasses.contains(className)) {
      return false;
    }
    
    // Look for component-like patterns
    final componentPatterns = [
      RegExp(r'^Base[A-Z]'),    // BaseButton, BaseCheckbox, etc.
      RegExp(r'^Ui[A-Z]'),      // UiButton, UiColors, etc.
      RegExp(r'(Size|State|Shape|Style|Config)$'), // CheckboxSize, CheckboxState, etc.
    ];
    
    return componentPatterns.any((pattern) => pattern.hasMatch(className));
  }

  /// Find which component provides a particular class
  String? _findComponentForClass(String className, Map<String, String> allComponents) {
    for (final entry in allComponents.entries) {
      final componentName = entry.key;
      final componentPath = entry.value;
      
      // Check brick template files
      final brickDir = Directory(path.join(componentPath, '__brick__'));
      try {
        if (brickDir.existsSync()) {
          for (final file in brickDir.listSync(recursive: true)) {
            if (file is File && file.path.endsWith('.dart')) {
              final content = file.readAsStringSync();
              if (_classDefinedInFile(content, className)) {
                return componentName;
              }
            }
          }
        }
      } catch (e) {
        // Continue searching other components
      }
    }
    
    return null;
  }

  /// Check if a class is defined in the given file content
  bool _classDefinedInFile(String content, String className) {
    final patterns = [
      RegExp('class\\s+$className\\s+'),
      RegExp('enum\\s+$className\\s+'),
      RegExp('typedef\\s+.*$className\\s+'),
      RegExp('mixin\\s+$className\\s+'),
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(content));
  }

  /// Include dependency component files in the main component's brick
  Future<void> _includeDependencyInBrick(
    String componentName,
    String componentPath,
    String dependencyName,
    Map<String, String> allComponents,
  ) async {
    try {
      final depPath = allComponents[dependencyName];
      if (depPath == null) {
        _logger.warn('    Dependency component $dependencyName not found');
        return;
      }
      
      final depBrickDir = Directory(path.join(depPath, '__brick__'));
      final targetBrickDir = Directory(path.join(componentPath, '__brick__'));
      
      if (!await depBrickDir.exists()) {
        _logger.warn('    Dependency brick not found for $dependencyName');
        return;
      }
      
      _logger.detail('    Including $dependencyName files in $componentName brick');
      
      // Copy dependency brick files to the target brick
      await for (final file in depBrickDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          final relativePath = path.relative(file.path, from: depBrickDir.path);
          final targetFile = File(path.join(targetBrickDir.path, relativePath));
          
          // Only copy if the file doesn't already exist to avoid conflicts
          if (!await targetFile.exists()) {
            await targetFile.parent.create(recursive: true);
            await file.copy(targetFile.path);
            _logger.detail('      Copied $relativePath');
          }
        }
      }
      
    } catch (e) {
      _logger.warn('    Failed to include dependency $dependencyName: $e');
    }
  }

  /// Add import statements for dependency components
  Future<void> _addImportStatements(String componentPath, Set<String> dependencies) async {
    try {
      final brickDir = Directory(path.join(componentPath, '__brick__'));
      
      // Process all Dart files in the brick template
      await for (final file in brickDir.list(recursive: true)) {
        if (file is File && file.path.endsWith('.dart')) {
          await _addImportsToFile(file, dependencies);
        }
      }
    } catch (e) {
      _logger.warn('    Failed to add import statements: $e');
    }
  }

  /// Add import statements to a specific file
  Future<void> _addImportsToFile(File file, Set<String> dependencies) async {
    try {
      final content = await file.readAsString();
      final fileName = path.basenameWithoutExtension(file.path);
      
      // Skip adding imports to dependency files themselves
      // Check if this file is one of the dependency files
      for (final dep in dependencies) {
        if (fileName == 'base_$dep') {
          return; // Don't add imports to the dependency file itself
        }
      }
      
      // Check if imports are needed (if the file references dependency classes)
      bool needsImports = false;
      for (final dep in dependencies) {
        final depClasses = _getExpectedClassesForComponent(dep);
        for (final className in depClasses) {
          if (content.contains(className)) {
            needsImports = true;
            break;
          }
        }
        if (needsImports) break;
      }
      
      if (!needsImports) return;
      
      // Check which imports already exist to avoid duplicates
      final existingImports = <String>{};
      final lines = content.split('\n');
      
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('import ')) {
          existingImports.add(trimmed);
        }
      }
      
      // Find the insertion point (after existing imports)
      int insertIndex = 0;
      
      // Find the last import statement
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trim().startsWith('import ')) {
          insertIndex = i + 1;
        } else if (lines[i].trim().isEmpty && insertIndex > 0) {
          // Keep empty lines after imports
          insertIndex = i + 1;
        } else if (insertIndex > 0 && lines[i].trim().isNotEmpty) {
          // Found non-empty line after imports, stop here
          break;
        }
      }
      
      // Add imports for dependencies that don't already exist
      final newImports = <String>[];
      for (final dep in dependencies) {
        final importStatement = "import 'base_$dep.dart';";
        if (!existingImports.contains(importStatement)) {
          newImports.add(importStatement);
        }
      }
      
      if (newImports.isNotEmpty) {
        // Insert imports
        lines.insertAll(insertIndex, newImports);
        
        // Add empty line after imports if not already present
        if (insertIndex + newImports.length < lines.length &&
            lines[insertIndex + newImports.length].trim().isNotEmpty) {
          lines.insert(insertIndex + newImports.length, '');
        }
        
        final updatedContent = lines.join('\n');
        await file.writeAsString(updatedContent);
        
        _logger.detail('      Added imports: ${newImports.join(', ')}');
      } else {
        _logger.detail('      All required imports already exist');
      }
      
    } catch (e) {
      _logger.warn('      Failed to add imports to ${path.basename(file.path)}: $e');
    }
  }

  /// Get expected class names for a component
  Set<String> _getExpectedClassesForComponent(String componentName) {
    // Common patterns for component class names
    final baseClassName = 'Base${componentName[0].toUpperCase()}${componentName.substring(1)}';
    
    return {
      baseClassName,
      '${componentName[0].toUpperCase()}${componentName.substring(1)}State',
      '${componentName[0].toUpperCase()}${componentName.substring(1)}Size',
      '${componentName[0].toUpperCase()}${componentName.substring(1)}Shape',
      '${componentName[0].toUpperCase()}${componentName.substring(1)}Style',
      '${componentName[0].toUpperCase()}${componentName.substring(1)}Config',
      '${componentName[0].toUpperCase()}${componentName.substring(1)}VisualState',
    };
  }
}

/// Information about a discovered widget.
/// 
/// Contains metadata about a widget found in the bricks directory,
/// including its name, location, and associated files.
class WidgetInfo {
  /// Constructor
  const WidgetInfo({
    required this.name,
    required this.path,
    required this.files,
  });

  /// The name of the widget (directory name)
  final String name;

  /// The full path to the widget directory
  final String path;

  /// List of Dart files in the widget directory (relative paths)
  final List<String> files;

  @override
  String toString() {
    return 'WidgetInfo(name: $name, path: $path, files: $files)';
  }
}
