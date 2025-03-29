#!/bin/bash

# Script to run the property_testing tests
# Usage: ./run_tests.sh [test_path] [options]

# Set default values
TEST_PATH=${1:-""}
REPORTER=${2:-"compact"}

# Print header
echo "Running Property Testing Tests"
echo "=============================="
echo ""

# Run the tests
if [ -z "$TEST_PATH" ]; then
  # Run all tests
  dart test --reporter=$REPORTER
else
  # Run specific test(s)
  dart test $TEST_PATH --reporter=$REPORTER
fi 