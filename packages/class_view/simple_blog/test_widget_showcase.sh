#!/bin/bash
echo "🧪 Testing Widget Showcase Endpoint..."
echo ""

# Start server in background
echo "Starting server..."
dart run bin/simple_blog.dart &
SERVER_PID=$!
sleep 3

echo ""
echo "Testing GET /api/widgets..."
curl -s http://localhost:8080/api/widgets | head -20
echo "..."

echo ""
echo ""
echo "Testing POST /api/widgets with valid data..."
curl -s -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{
    "text_required": "Hello World",
    "email": "user@example.com",
    "checkbox": true,
    "choice_single": "option1"
  }' | head -10
echo "..."

echo ""
echo ""
echo "Testing POST with invalid data (missing required field)..."
curl -s -X POST http://localhost:8080/api/widgets \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com"
  }' | head -10
echo "..."

# Cleanup
echo ""
echo ""
echo "Stopping server..."
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo ""
echo "✅ Widget Showcase tests complete!"
