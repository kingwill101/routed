# Root justfile for routed_ecosystem monorepo
# Manages all packages in the ecosystem

# List all packages
PACKAGES := "packages/property_testing packages/routed packages/routed_cli packages/routed_hotwire packages/server_testing/routed_testing packages/server_testing/server_testing packages/server_testing/server_testing_shelf"

# Default recipe - shows available commands
default:
    @just --list

# Install dependencies for all packages
get-all:
    @echo "📦 Installing dependencies for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → $pkg"; \
        (cd "$pkg" && dart pub get) || exit 1; \
    done
    @echo "✅ All dependencies installed"

# Run tests for all packages
test-all:
    @echo "🧪 Running tests for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Testing $pkg"; \
        (cd "$pkg" && dart test) || exit 1; \
    done
    @echo "✅ All tests passed"

# Run tests for all packages with coverage
test-coverage:
    @echo "🧪 Running tests with coverage for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Testing $pkg"; \
        (cd "$pkg" && dart test --coverage=coverage && dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib) || exit 1; \
    done
    @echo "✅ All tests completed with coverage"

# Analyze all packages
analyze-all:
    @echo "🔍 Analyzing all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Analyzing $pkg"; \
        (cd "$pkg" && dart analyze) || exit 1; \
    done
    @echo "✅ All packages analyzed"

# Format all packages
format-all:
    @echo "✨ Formatting all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Formatting $pkg"; \
        (cd "$pkg" && dart format .); \
    done
    @echo "✅ All packages formatted"

# Check formatting for all packages (CI)
format-check:
    @echo "✨ Checking format for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Checking $pkg"; \
        (cd "$pkg" && dart format --output=none --set-exit-if-changed .) || exit 1; \
    done
    @echo "✅ All packages properly formatted"

# Fix all packages
fix-all:
    @echo "🔧 Applying fixes to all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Fixing $pkg"; \
        (cd "$pkg" && dart fix --apply); \
    done
    @echo "✅ All packages fixed"

# Upgrade dependencies for all packages
upgrade-all:
    @echo "⬆️  Upgrading dependencies for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Upgrading $pkg"; \
        (cd "$pkg" && dart pub upgrade); \
    done
    @echo "✅ All dependencies upgraded"

# Outdated dependencies for all packages
outdated-all:
    @echo "📊 Checking outdated dependencies for all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Checking $pkg"; \
        (cd "$pkg" && dart pub outdated); \
    done

# Clean all packages
clean-all:
    @echo "🧹 Cleaning all packages..."
    @for pkg in {{PACKAGES}}; do \
        echo "  → Cleaning $pkg"; \
        (cd "$pkg" && rm -rf .dart_tool build coverage); \
    done
    @echo "✅ All packages cleaned"

# Run full CI check (format check, analyze, test)
ci: format-check analyze-all test-all
    @echo "✅ CI checks passed"

# Prepare for release (clean, get, analyze, test)
pre-release: clean-all get-all analyze-all test-all
    @echo "✅ Ready for release"

# Run a specific package command
run-in PACKAGE COMMAND:
    @echo "🏃 Running '{{COMMAND}}' in {{PACKAGE}}..."
    @cd {{PACKAGE}} && {{COMMAND}}

# List all packages
list-packages:
    @echo "📦 Packages in this monorepo:"
    @for pkg in {{PACKAGES}}; do \
        echo "  • $pkg"; \
    done
