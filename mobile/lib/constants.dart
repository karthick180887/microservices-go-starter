import 'package:flutter/foundation.dart';

class Constants {
  // API Configuration
  static final String apiUrl = _resolveApiUrl();

  static final String websocketUrl = _resolveWebsocketUrl();

  static String _resolveApiUrl() {
    const envValue = String.fromEnvironment('API_URL', defaultValue: '');
    if (envValue.isNotEmpty) {
      return envValue;
    }

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isiOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isAndroid) {
      // 10.0.6.3 allows Android emulators to reach the host machine
      return 'http://10.0.6.3:8081';
    }

    if (isiOS) {
      // iOS simulators can use localhost directly
      return 'http://localhost:8081';
    }

    // Fallback for desktop/web builds
    return 'http://localhost:8081';
  }

  static String _resolveWebsocketUrl() {
    const envValue = String.fromEnvironment('WEBSOCKET_URL', defaultValue: '');
    if (envValue.isNotEmpty) {
      return envValue;
    }

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isiOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isAndroid) {
      return 'ws://10.0.6.3:8081/ws';
    }

    if (isiOS) {
      return 'ws://localhost:8081/ws';
    }

    return 'ws://localhost:8081/ws';
  }

  // Default location (Chennai, India)
  static const double defaultLatitude = 13.0827;
  static const double defaultLongitude = 80.2707;

  // Stripe
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
}

