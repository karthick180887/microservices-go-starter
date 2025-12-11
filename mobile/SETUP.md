# Flutter Ride Sharing App - Setup Guide

## Prerequisites

1. **Flutter SDK**: Install Flutter (version 3.0.0 or higher)
   ```bash
   flutter --version
   ```

2. **Dependencies**: Install all dependencies
   ```bash
   cd mobile
   flutter pub get
   ```

## Configuration

### 1. Google Maps API Key

#### Android
1. Get your Google Maps API key from [Google Cloud Console](https://console.cloud.google.com/)
2. Open `android/app/src/main/AndroidManifest.xml`
3. Replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_ACTUAL_API_KEY"/>
   ```

#### iOS
1. Open `ios/Runner/AppDelegate.swift`
2. Replace `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key:
   ```swift
   GMSServices.provideAPIKey("YOUR_ACTUAL_API_KEY")
   ```

### 2. API Configuration

Update `lib/constants.dart` with your backend URLs:

```dart
static const String apiUrl = 'http://your-api-url:8081';
static const String websocketUrl = 'ws://your-websocket-url:8081/ws';
```

Or set them as environment variables when running:
```bash
flutter run --dart-define=API_URL=http://localhost:8081 --dart-define=WEBSOCKET_URL=ws://localhost:8081/ws
```

### 3. Stripe Configuration

1. Get your Stripe publishable key from [Stripe Dashboard](https://dashboard.stripe.com/)
2. Update `lib/constants.dart`:
   ```dart
   static const String stripePublishableKey = 'YOUR_STRIPE_PUBLISHABLE_KEY';
   ```

Or set as environment variable:
```bash
flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
```

## Running the App

### Development
```bash
flutter run
```

### Build for Android
```bash
flutter build apk
```

### Build for iOS
```bash
flutter build ios
```

## Project Structure

```
mobile/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── constants.dart             # App constants and configuration
│   ├── models/                    # Data models
│   │   ├── types.dart             # Core data types
│   │   └── contracts.dart         # API contracts and message types
│   ├── services/                  # Business logic services
│   │   ├── api_service.dart       # HTTP API client
│   │   ├── websocket_service.dart # WebSocket client
│   │   └── stripe_service.dart   # Stripe payment integration
│   ├── providers/                 # State management (Riverpod)
│   │   ├── rider_provider.dart   # Rider state management
│   │   └── driver_provider.dart  # Driver state management
│   ├── screens/                   # App screens
│   │   ├── home_screen.dart       # Welcome/selection screen
│   │   ├── package_screen.dart    # Car package selection
│   │   ├── rider_map_screen.dart  # Rider map interface
│   │   ├── driver_map_screen.dart # Driver map interface
│   │   └── payment_success_screen.dart
│   ├── widgets/                   # Reusable widgets
│   │   ├── rider_trip_overview.dart
│   │   ├── driver_trip_overview.dart
│   │   ├── driver_card.dart
│   │   ├── stripe_payment_button.dart
│   │   └── ...
│   └── utils/                     # Utility functions
│       ├── geohash_utils.dart
│       └── math_utils.dart
├── android/                       # Android configuration
├── ios/                           # iOS configuration
└── pubspec.yaml                   # Flutter dependencies
```

## Features

### Rider Features
- Interactive map with tap-to-select destination
- Real-time driver locations via WebSocket
- Trip preview with route and fare options
- Payment integration with Stripe
- Trip status tracking

### Driver Features
- Interactive map for location updates
- Real-time trip request notifications
- Accept/decline trip requests
- Route visualization for accepted trips
- Car package selection (Sedan, SUV, Van, Luxury)

## Troubleshooting

### Google Maps not showing
- Verify API key is correctly set in both Android and iOS configs
- Ensure Google Maps API is enabled in Google Cloud Console
- Check that billing is enabled for your Google Cloud project

### WebSocket connection issues
- Verify backend is running and accessible
- Check network connectivity
- Review WebSocket URL in constants.dart

### Payment not working
- Verify Stripe publishable key is set
- Check Stripe API key is valid
- Ensure backend payment service is configured

## Notes

- The app uses Riverpod for state management
- WebSocket connections are managed automatically
- Location updates for drivers are sent every 5 seconds
- Map interactions are debounced to prevent excessive API calls

