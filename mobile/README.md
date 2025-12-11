# Ride Sharing Flutter App

Flutter mobile application for the ride-sharing platform.

## Features

- **Rider Mode**: Request rides, select destinations, view drivers, and make payments
- **Driver Mode**: Accept/decline trip requests, view routes, and manage trips
- **Real-time Updates**: WebSocket connections for live driver locations and trip status
- **Interactive Maps**: Google Maps integration with markers and route visualization
- **Payment Integration**: Stripe payment processing

## Setup

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Configure API endpoints in `lib/constants.dart`:
```dart
const String apiUrl = 'http://localhost:8081';
const String websocketUrl = 'ws://localhost:8081/ws';
```

3. For Google Maps, add your API key in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/AppDelegate.swift`

4. For Stripe, configure your publishable key in `lib/services/stripe_service.dart`

## Running the App

```bash
flutter run
```

## Project Structure

```
lib/
├── main.dart
├── constants.dart
├── models/          # Data models
├── services/        # API, WebSocket, and other services
├── providers/       # Riverpod state management
├── screens/         # App screens
├── widgets/         # Reusable widgets
└── utils/           # Utility functions
```

