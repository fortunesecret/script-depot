# Electron Project Initializer

A PowerShell script for quickly bootstrapping Electron projects with TypeScript or JavaScript support. This tool automates the setup process, allowing you to create new Electron applications with a single command.

## Features

- Creates a complete Electron project structure
- Supports both TypeScript and JavaScript
- Configures package.json with proper scripts and dependencies
- Includes template files for main process, renderer process, and preload scripts
- Allows custom project location, name, author, and version
- Supports adding extra dependencies during initialization
- Includes a test script to verify functionality

## Requirements

- PowerShell 5.1 or higher
- Node.js and npm installed
- Windows operating system

## Installation

1. Clone or download this repository
2. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Basic Usage

To create a new Electron project with default settings (TypeScript):

```powershell
.\init.ps1
```

This will create a new project named "my-electron-app" in the default directory (`C:\source\repos\my-electron-app`).

### Command Line Parameters

| Parameter | Description | Default |
|-----------|-------------|--------|
| `BaseDirectory` | Base directory where the project folder will be created | `C:\source\repos` |
| `ProjectName` | Name of the project | `my-electron-app` |
| `Author` | Author name for package.json | `""` (empty string) |
| `Version` | Project version | `0.0.1` |
| `UseTypeScript` | Whether to use TypeScript | `$true` |
| `ExtraDependencies` | Additional npm packages to install | `@()` (empty array) |

### Examples

#### Create a JavaScript Project

```powershell
.\init.ps1 -ProjectName "js-electron-app" -UseTypeScript $false
```

#### Create a Project in a Custom Location

```powershell
.\init.ps1 -ProjectName "custom-location-app" -BaseDirectory "D:\projects"
```

#### Create a Project with Extra Dependencies

```powershell
.\init.ps1 -ProjectName "feature-rich-app" -ExtraDependencies @("electron-store", "axios")
```

#### Full Example with All Parameters

```powershell
.\init.ps1 -BaseDirectory "D:\projects" -ProjectName "complete-app" -Author "Your Name" -Version "1.0.0" -UseTypeScript $true -ExtraDependencies @("electron-store", "axios")
```

## Project Structure

The generated project will have the following structure:

```
project-name/
├── node_modules/
├── dist/           # Compiled JavaScript (TypeScript projects only)
├── index.html      # Main HTML file
├── main.ts/js      # Main process script
├── preload.ts/js   # Preload script
├── renderer.ts/js  # Renderer process script
├── package.json    # Project configuration
└── tsconfig.json   # TypeScript configuration (TypeScript projects only)
```

## Testing

A comprehensive test script is included to verify the functionality of the initialization script:

```powershell
.\test-init.ps1 [-Verbose] [-KeepTestDir] [-BuildAndRun]
```

### Test Script Options

| Parameter | Description |
|-----------|-------------|
| `-Verbose` | Show detailed output during testing, including command execution details |
| `-KeepTestDir` | Keep the test directory after testing (useful for manual inspection) |
| `-BuildAndRun` | Build (TypeScript only) and run each generated app to verify they work out of the box |

### Test Coverage

The test script performs the following verifications:

1. **TypeScript project creation**
   - Verifies project directory creation
   - Checks for required files (package.json, tsconfig.json, index.html, main.ts, etc.)
   - Validates package.json content and scripts

2. **JavaScript project creation**
   - Verifies project directory creation
   - Checks for required files (package.json, index.html, main.js, etc.)
   - Validates package.json content and scripts

3. **Extra dependencies installation**
   - Verifies that specified extra dependencies are properly installed
   - Tests both TypeScript and JavaScript projects with extra dependencies

4. **Build and run verification** (with `-BuildAndRun`)
   - Builds TypeScript projects using `npm run build`
   - Launches each application using `npm start`
   - Verifies successful startup without errors
   - Automatically terminates processes after verification

### Process Management

When using the `-BuildAndRun` option, the script includes robust process management:

- Automatically identifies and terminates all Electron processes before cleanup
- Implements retry logic for directory cleanup to handle locked files
- Provides detailed error reporting for any issues encountered

### Example Usage

```powershell
# Basic testing
.\test-init.ps1

# Detailed output
.\test-init.ps1 -Verbose

# Full verification including build and run
.\test-init.ps1 -Verbose -BuildAndRun

# Keep test directories for manual inspection
.\test-init.ps1 -Verbose -BuildAndRun -KeepTestDir
```

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.
