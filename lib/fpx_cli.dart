import 'dart:io';
import 'package:mason/mason.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Main CLI runner class
class FpxCli {
  final Logger logger;

  FpxCli({Logger? logger}) : logger = logger ?? Logger();

  /// Run the CLI with given arguments
  Future<int> run(List<String> args) async {
    try {
      if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
        printUsage();
        return 0;
      }

      final command = args[0];

      switch (command) {
        case 'add':
          await handleAddCommand(args.sublist(1));
          break;
        case 'init':
          await handleInitCommand(args.sublist(1));
          break;
        case 'list':
          await handleListCommand();
          break;
        default:
          logger.err('❌ Unknown command "$command". Try "fpx --help"');
          return 1;
      }
      return 0;
    } catch (e, stackTrace) {
      logger.err('❌ Unexpected error: $e');
      logger.detail('Stack trace: $stackTrace');
      return 1;
    }
  }

  void printUsage() {
    print('''
fpx - Flutter eXports CLI

Usage:
  fpx init                                 Initialize a new mason.yaml file
  fpx add <component> [options]            Add a component using Mason bricks
  fpx list                                List available bricks

Options for 'add':
  --name=<n>           Component name (required for most bricks)
  --variant=<variant>     Component variant
  --path=<path>          Target path (default: current directory)
  --source=<url>         Remote brick source URL

Examples:
  fpx init
  fpx add button --name=LoginButton --variant=primary
  fpx add card --source=https://github.com/my-org/ui-bricks.git
  fpx list
''');
  }

  Future<void> handleAddCommand(List<String> args) async {
    if (args.isEmpty) {
      logger.err('❌ Missing component name. Usage: fpx add <component>');
      throw ArgumentError('Missing component name');
    }

    // Auto-initialize if mason.yaml doesn't exist
    await ensureMasonYamlExists();

    final component = args[0];
    final extraArgs = args.sublist(1);

    try {
      // Parse additional arguments
      final parser = ArgParser()
        ..addOption('name', help: 'Component name')
        ..addOption('variant', help: 'Component variant')
        ..addOption('path', help: 'Target path', defaultsTo: '.')
        ..addOption('source', help: 'Brick source URL');

      final parsedArgs = parser.parse(extraArgs);
      
      // Get target directory
      final targetPath = parsedArgs['path'] as String;
      final targetDirectory = Directory(path.isAbsolute(targetPath) 
          ? targetPath 
          : path.join(Directory.current.path, targetPath));

      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      // Find or create brick
      final brick = await findBrick(component, parsedArgs['source'] as String?);
      
      // Create generator from brick
      final generator = await MasonGenerator.fromBrick(brick);

      // Create variables map from parsed arguments
      final vars = <String, dynamic>{};
      if (parsedArgs['name'] != null) vars['name'] = parsedArgs['name'];
      if (parsedArgs['variant'] != null) vars['variant'] = parsedArgs['variant'];
      
      // Add component name as default variable
      vars['component'] = component;

      // Prompt for any missing required variables
      await promptForMissingVars(generator, vars);
      
      // Generate the component
      final target = DirectoryGeneratorTarget(targetDirectory);
      final files = await generator.generate(target, vars: vars, logger: logger);
      
      logger.success('✅ Successfully generated $component component!');
      logger.info('Generated ${files.length} file(s):');
      for (final file in files) {
        logger.detail('  ${file.path}');
      }
      
    } catch (e, stackTrace) {
      logger.err('❌ Failed to generate component: $e');
      logger.detail('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> handleInitCommand(List<String> args) async {
    final masonYamlFile = File('mason.yaml');
    
    if (await masonYamlFile.exists()) {
      logger.warn('⚠️  mason.yaml already exists');
      return;
    }

    await ensureMasonYamlExists();
    logger.info('📝 Add your bricks to mason.yaml and run "fpx add <brick-name>"');
  }

  Future<void> handleListCommand() async {
    // Auto-initialize if mason.yaml doesn't exist
    await ensureMasonYamlExists();
    
    final masonYaml = await loadMasonYaml();
    
    final bricksNode = masonYaml?['bricks'];
    if (bricksNode == null || (bricksNode is Map && bricksNode.isEmpty)) {
      logger.info('📋 No bricks configured in mason.yaml yet');
      logger.info('💡 Add bricks to mason.yaml or use --source option with fpx add');
      return;
    }

    logger.info('Available bricks:');
    if (bricksNode is Map) {
      for (final brickName in bricksNode.keys) {
        logger.info('  $brickName');
      }
    }
  }

  Future<Brick> findBrick(String component, String? source) async {
    // If source is provided, try to use it as a Git URL or path
    if (source != null) {
      if (source.startsWith('http') || source.contains('github.com')) {
        // Handle remote Git repository
        logger.info('Fetching brick from remote source: $source');
        return Brick.git(GitPath(source));
      } else if (await Directory(source).exists()) {
        // Handle local path
        return Brick.path(source);
      }
    }

    // Try to find brick in mason.yaml
    final masonYaml = await loadMasonYaml();
    if (masonYaml != null) {
      final bricksNode = masonYaml['bricks'];
      if (bricksNode is Map && bricksNode.containsKey(component)) {
        final brickConfig = bricksNode[component];
        
        // Handle different brick source types
        if (brickConfig is Map && brickConfig.containsKey('git')) {
          final gitConfig = brickConfig['git'];
          if (gitConfig is Map) {
            final url = gitConfig['url'] as String;
            final gitPath = gitConfig.containsKey('path') 
                ? GitPath(url, path: gitConfig['path'] as String)
                : GitPath(url);
            return Brick.git(gitPath);
          }
        } else if (brickConfig is Map && brickConfig.containsKey('path')) {
          final brickPath = brickConfig['path'] as String;
          return Brick.path(brickPath);
        }
      }
    }

    // If no brick found, suggest creating mason.yaml
    throw Exception('Brick "$component" not found. Please add it to mason.yaml or use --source option.\nRun "fpx init" to create a mason.yaml file.');
  }

  Future<Map<String, dynamic>?> loadMasonYaml() async {
    final masonYamlFile = File('mason.yaml');
    if (!await masonYamlFile.exists()) {
      return null;
    }

    try {
      final content = await masonYamlFile.readAsString();
      final yamlMap = loadYaml(content);
      
      if (yamlMap is Map) {
        return Map<String, dynamic>.from(yamlMap);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> ensureMasonYamlExists() async {
    final masonYamlFile = File('mason.yaml');
    
    if (!await masonYamlFile.exists()) {
      logger.info('📦 No mason.yaml found, creating one with default settings...');
      
      const defaultMasonYaml = '''
bricks:
  # Add your bricks here
  # Example:
  # button:
  #   git:
  #     url: https://github.com/felangel/mason.git
  #     path: bricks/button
  # 
  # widget:
  #   path: ./bricks/widget
''';

      await masonYamlFile.writeAsString(defaultMasonYaml);
      logger.success('✅ Created mason.yaml with default configuration');
    }
  }

  Future<void> promptForMissingVars(MasonGenerator generator, Map<String, dynamic> vars) async {
    // Get brick variables from the generator
    try {
      // For Mason generators, we can't easily access brick variables at runtime
      // So we'll just warn about common missing variables
      final commonVars = ['name', 'description', 'component'];
      
      for (final varName in commonVars) {
        if (!vars.containsKey(varName)) {
          logger.detail('Variable $varName not provided, using defaults if available');
        }
      }
    } catch (e) {
      // If we can't read brick variables, continue with provided vars
      logger.detail('Could not read brick variables: $e');
    }
  }
}
