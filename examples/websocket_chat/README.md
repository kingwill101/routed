# WebSocket Chat Example

This example demonstrates how to use WebSocket functionality in the Routed framework to create a simple chat
application.

## Features

- Real-time chat messaging
- User join/leave notifications
- Nickname changing with `/nick` command
- Simple web interface
- Broadcast messaging to all connected clients

## Running the Example

1. Make sure you have all dependencies installed:
   ```bash
   dart pub get
   ```

2. Run the server:
   ```bash
   dart run main.dart
   ```

3. Open your browser and navigate to:
   ```
   http://localhost:3000
   ```

4. Open multiple browser windows to test chat functionality between different clients.

## Usage

- Type a message and press Enter or click Send to broadcast it to all connected users
- Use the `/nick <username>` command to change your nickname
- All connected users will see join/leave notifications and nickname changes

## Implementation Details

The example consists of two main parts:

1. **Server (`main.dart`)**
    - Implements a `ChatHandler` that extends `WebSocketHandler`
    - Manages connected clients and message broadcasting
    - Handles client lifecycle events (connect, disconnect, errors)
    - Processes chat commands like `/nick`

2. **Client (`public/index.html`)**
    - Simple web interface for the chat
    - Connects to the WebSocket server
    - Displays messages and system notifications
    - Handles user input and message sending

## Code Structure

- `ChatClient` class: Represents a connected chat user
- `ChatHandler` class: Handles WebSocket connections and message routing
- Static file serving for the web interface
- WebSocket endpoint at `/chat` 