# FPX - Local Development

This guide covers local development, testing, and contributing to the FPX CLI tool.

## Local Development Setup 🛠️

### Prerequisites

- Dart SDK (latest stable version)
- Git

### Getting the Source Code

```sh
git clone https://github.com/jdde/fpx.git
cd fpx
```

### Installing Dependencies

```sh
dart pub get
```

### Running Locally

You can run the CLI locally without installing it globally:

```sh
# Run directly from source
dart run bin/fpx.dart --help

# Or activate locally for development
dart pub global activate --source=path .
```

### Local Installation

To install locally for testing:

```sh
dart pub global activate --source=path <path to this package>
```

## Development Commands

### Testing the CLI

```sh
# Show help
dart run bin/fpx.dart --help

# Test repository management
dart run bin/fpx.dart repository add --url https://github.com/unping/unping-ui
dart run bin/fpx.dart repository list
dart run bin/fpx.dart repository remove --name felangel

# Test other commands
dart run bin/fpx.dart init
dart run bin/fpx.dart list
```

## Running Tests with Coverage 🧪

### Running Tests

To run all unit tests:

```sh
dart test
```

### Coverage Reports

To run tests with coverage:

```sh
# Install coverage tool
dart pub global activate coverage 1.2.0

# Run tests with coverage
dart test --coverage=coverage

# Format coverage data
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

### Viewing Coverage Reports

To view the generated coverage report you can use [lcov](https://github.com/linux-test-project/lcov):

```sh
# Generate Coverage Report
genhtml coverage/lcov.info -o coverage/

# Open Coverage Report
open coverage/index.html
```

## Project Structure

```
fpx/
├── bin/
│   └── fpx.dart              # CLI entry point
├── lib/
│   ├── fpx.dart              # Main library export
│   └── src/
│       ├── command_runner.dart
│       ├── version.dart
│       ├── commands/         # All CLI commands
│       └── services/         # Business logic
├── test/                     # Unit tests
└── README.md                 # User documentation
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and add tests
4. Run tests: `dart test`
5. Run code formatting: `dart format .`
6. Run analysis: `dart analyze`
7. Commit your changes: `git commit -am 'Add some feature'`
8. Push to the branch: `git push origin feature/my-feature`
9. Submit a pull request

## Development Workflow

### Code Quality

The project uses:
- **dart format** for code formatting
- **dart analyze** for static analysis
- **very_good_analysis** for linting rules

Run quality checks:

```sh
# Format code
dart format .

# Analyze code
dart analyze

# Run all tests
dart test
```

### Testing Strategy

- Unit tests for all commands and services
- Integration tests for CLI workflows
- Coverage target: >90%

### Release Process

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Run tests and ensure coverage
4. Create a release tag
5. Publish to pub.dev (if applicable)

---

For user documentation, see [README.md](README.md).
