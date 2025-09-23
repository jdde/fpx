# Reusable GitHub Action for Ensuring fpx Compatibility

This repository provides a reusable GitHub Action that ensures Flutter components are compatible with fpx by testing component installation, compilation, and dependency analysis directly from the repository where it's executed.

## Features

- 🚀 **Automated fpx Installation**: Installs fpx globally and sets up the environment
- 📦 **Self-Repository Testing**: Tests components from the repository where the action runs
- 🔍 **Compatibility Analysis**: Validates fpx compatibility and dependency requirements
- ✅ **Compilation Testing**: Tests if components compile successfully via fpx
- 📊 **Detailed Reporting**: Generates comprehensive fpx compatibility reports
- 🏗️ **CI/CD Ready**: Easy integration into component library workflows

## Quick Start

### 1. Using the Reusable Workflow in Your Component Library

Create a workflow file in your component library repository (e.g., `.github/workflows/ensure-fpx-compatibility.yml`):

```yaml
name: 'Ensure fpx Compatibility'

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
    inputs:
      component_name:
        description: 'Component name to test for fpx compatibility'
        required: true
        default: 'base_button'

jobs:
  ensure-fpx-compatibility:
    uses: jdde/fpx/.github/workflows/reusable-fpx-compatibility.yml@main
    with:
      component_name: ${{ github.event.inputs.component_name || 'base_button' }}
      flutter_version: 'stable'
      repository_name: 'my-components'
```

### 2. Testing Multiple Components for fpx Compatibility

```yaml
name: 'Ensure All Components Compatible'

on: [push, pull_request]

jobs:
  ensure-compatibility:
    strategy:
      matrix:
        component: 
          - 'base_button'
          - 'base_badge'
          - 'base_input'
          - 'base_checkbox'
    uses: jdde/fpx/.github/workflows/reusable-fpx-compatibility.yml@main
    with:
      component_name: ${{ matrix.component }}
      flutter_version: 'stable'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `component_name` | Name of the component to test for fpx compatibility | Yes | - |
| `flutter_version` | Flutter version to use | No | `stable` |
| `repository_name` | Name for the repository in fpx | No | Auto-generated |

## Outputs

| Output | Description | Type |
|--------|-------------|------|
| `fpx_compatible` | Whether the component is compatible with fpx | boolean |
| `component_installed` | Whether fpx component installation succeeded | boolean |
| `compilation_success` | Whether component compiles successfully | boolean |
| `has_dependency_issues` | Whether dependency issues were found | boolean |
| `third_party_dependencies` | Comma-separated list of third-party deps | string |

## What the Action Does

### 1. Environment Setup
- Checks out the current repository (component library)
- Installs Flutter with the specified version
- Installs fpx globally via `dart pub global activate fpx`
- Creates a test Flutter project

### 2. fpx Integration
- Automatically detects the current repository URL
- Adds the current repository to fpx
- Lists available components for verification
- Attempts to install the specified component via fpx

### 3. Compatibility Analysis
- Runs `dart analyze` to detect compilation issues
- Extracts import statements from component files
- Identifies third-party package dependencies
- Excludes standard Flutter/Dart packages (`flutter/`, `meta/`, etc.)

### 4. Compilation Testing
- Tests component compilation with `flutter analyze --no-pub`
- Reports compilation success/failure

### 5. Reporting
- Generates detailed fpx compatibility reports in Markdown format
- Uploads test artifacts including:
  - Component source files
  - Analysis output
  - README files from components
  - Compatibility summary reports

## Example Output

The action generates a comprehensive fpx compatibility report like this:

```markdown
## fpx Compatibility Report

**Component:** base_button
**Repository:** my-org/my-component-library
**Commit:** abc123def456
**Flutter Version:** stable

✅ **fpx Component Installation:** Success
✅ **Component Compilation:** Success
✅ **Dependency Analysis:** No issues found

**Third-party Dependencies Required:**
```
google_fonts
another_package
```

**Generated on:** 2024-12-19 10:30:45 UTC
```

## Advanced Usage

### Custom Analysis

You can extend the workflow by accessing the outputs:

```yaml
jobs:
  ensure-fpx-compatibility:
    uses: jdde/fpx/.github/workflows/reusable-fpx-compatibility.yml@main
    with:
      component_name: 'custom_widget'
      
  custom-analysis:
    needs: ensure-fpx-compatibility
    runs-on: ubuntu-latest
    steps:
      - name: Check fpx compatibility results
        run: |
          echo "fpx compatible: ${{ needs.ensure-fpx-compatibility.outputs.fpx_compatible }}"
          echo "Component installed: ${{ needs.ensure-fpx-compatibility.outputs.component_installed }}"
          echo "Compilation successful: ${{ needs.ensure-fpx-compatibility.outputs.compilation_success }}"
          echo "Dependencies: ${{ needs.ensure-fpx-compatibility.outputs.third_party_dependencies }}"
```

### Matrix Testing with Different Flutter Versions

```yaml
jobs:
  test-flutter-versions:
    strategy:
      matrix:
        flutter_version: ['3.16.0', '3.19.0', 'stable']
        component: ['base_button', 'base_input']
    uses: jdde/fpx/.github/workflows/reusable-fpx-compatibility.yml@main
    with:
      component_name: ${{ matrix.component }}
      flutter_version: ${{ matrix.flutter_version }}
```

## Requirements

- Repository must be compatible with fpx
- Components should follow fpx brick structure
- Repository must be publicly accessible or action must run with appropriate permissions

## Troubleshooting

### Common Issues

1. **Component not found**: Ensure the component exists in your repository and follows fpx conventions
2. **Compilation failures**: Check if the component has undeclared dependencies
3. **fpx installation issues**: Verify Dart/Flutter environment setup
4. **Repository access**: Ensure the repository is publicly accessible or has proper permissions

### Debugging

Enable detailed logging by adding to your workflow:

```yaml
env:
  FLUTTER_VERBOSE: true
  PUB_VERBOSE: true
```

## Contributing

Feel free to submit issues and enhancement requests to improve this action!

## License

This action is distributed under the same license as the fpx project.
