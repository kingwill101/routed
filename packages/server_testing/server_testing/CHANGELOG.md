## Unreleased

### Added

- Switched the browser logging stack to the `contextual` package with
  structured contexts (`logger.info('...', context: Context({...}))`).
- Toggle browser bootstrap logging via `SERVER_TESTING_DISABLE_LOGS` /
  `SERVER_TESTING_ENABLE_LOGS` and the new `BrowserConfig.loggingEnabled`
  flag.
- Added binary override support (`BrowserConfig.binaryOverrides` and
  `SERVER_TESTING_<BROWSER>_BINARY` env vars) to reuse existing Chromium/
  Firefox installations in CI environments.
- Export `BrowserLogger`, `BrowserException`, and `BrowserPaths` from the
  public browser surface so downstream packages can reach the full testing API.

## 0.1.0

### Features

#### Browser Testing Framework

- **Complete browser testing implementation** with support for Firefox and Chromium
- **Synchronous and asynchronous browser APIs** for flexible test writing
- **Browser types**: Firefox and Chromium implementations with full WebDriver integration
- **Enhanced waiter utilities** for reliable element detection and state waiting
- **Device emulation support** with predefined device profiles
- **Screenshot management** with automatic capture on test failures

#### Driver Management

- **Automatic driver installation** for ChromeDriver and GeckoDriver
- **Version resolution** system for compatible driver downloads
- **Force reinstall support** for both browsers and drivers via `--force` flag
- **Binary management** with platform-specific handling (Linux, macOS, Windows)
- **Lock-based installation** to prevent race conditions during parallel test runs

#### CLI Tool

- `install [browserNames...] [--force|-f]` - Install/verify browsers from browsers.json
- `install:driver [chrome|firefox] [--force|-f]` - Setup driver servers
- `init` - Scaffold test configuration and directory structure
- `create:browser <name>` - Generate browser test templates
- `create:http <name>` - Generate HTTP test templates

#### Testing Utilities

- **HTTP testing framework** with TestClient and TestResponse
- **Request assertions** with fluent API (assertStatus, assertJson, assertHeader, etc.)
- **Mock request/response builders** for unit testing
- **Multipart form data builder** for file upload testing
- **Numeric assertions** for testing numeric values
- **Custom request handlers** interface for framework integration

#### Component & Page Object Support

- **Component base class** with ergonomic APIs (`scope`, `find`, `click`, `type`, `exists`, `within`)
- **Page object pattern** implementation for structured browser tests
- **Nested component support** for complex UI testing
- **Shared mocks** in `test/_support` for reusable test fixtures

#### Configuration & Setup

- **BrowserConfig** with extensive options (headless, window size, arguments, capabilities)
- **Browser bootstrap system** with registry-based executable management
- **Proxy support** for network interception
- **Custom browser paths** and binary configuration
- **browsers.json** configuration file for project-specific browser setup

#### Error Handling & Debugging

- **Enhanced error messages** with context and suggestions
- **Browser logger** with configurable verbosity and file output
- **Screenshot on failure** with automatic test log directory management
- **Stack trace enhancement** for better debugging

### Tests

#### Integration Tests

- Real browser testing with Firefox headless
- Screenshot capture and PNG signature verification
- Device emulation integration tests
- Parallel browser group execution
- Laravel Dusk-style API integration tests
- Page object and component real browser tests

#### Unit Tests

- Browser configuration validation
- Synchronous/asynchronous API consistency
- Enhanced waiter behavior
- Component model with Mockito
- Laravel Dusk-style assertions
- Page enhancements and conveniences

#### Installation Tests

- Browser binary installation verification
- Browser bundle reinstall with force flag

### Deprecations

None - Initial release
