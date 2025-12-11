import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contracts.dart';
import '../models/types.dart';
import '../services/websocket_service.dart';
import 'dart:async';

class DriverState {
  final Trip? requestedTrip;
  final TripEvents? tripStatus;
  final Driver? driver;
  final String? error;

  DriverState({
    this.requestedTrip,
    this.tripStatus,
    this.driver,
    this.error,
  });

  DriverState copyWith({
    Trip? requestedTrip,
    TripEvents? tripStatus,
    Driver? driver,
    String? error,
  }) {
    return DriverState(
      requestedTrip: requestedTrip ?? this.requestedTrip,
      tripStatus: tripStatus ?? this.tripStatus,
      driver: driver ?? this.driver,
      error: error ?? this.error,
    );
  }
}

class DriverNotifier extends StateNotifier<DriverState> {
  final WebSocketService _wsService;
  final String userId;
  final CarPackageSlug packageSlug;
  StreamSubscription<ServerWsMessage>? _messageSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _disposed = false;
  Coordinate? _initialLocation;
  String? _initialGeohash;

  DriverNotifier(this._wsService, this.userId, this.packageSlug)
      : super(DriverState()) {
    _connect();
  }
  
  bool get mounted => !_disposed;

  void setInitialLocation(Coordinate location, String geohash) {
    _initialLocation = location;
    _initialGeohash = geohash;
    // If already connected, send location immediately
    if (_wsService.isConnected) {
      _wsService.sendLocation(location, geohash: geohash);
    }
  }

  void _connect() {
    _wsService.connect(
      BackendEndpoints.wsDrivers.value,
      queryParams: {
        'userID': userId,
        'packageSlug': packageSlug.value,
      },
      initialLocation: _initialLocation,
      geohash: _initialGeohash,
    );

    _messageSubscription = _wsService.messageStream.listen((message) {
      if (!mounted) return;
      
      switch (message.type) {
        case TripEvents.driverTripRequest:
          if (message is DriverTripRequestMessage) {
            state = state.copyWith(
              requestedTrip: message.data,
              tripStatus: message.type,
            );
          }
          break;
        case TripEvents.driverRegister:
          if (message is DriverRegisterMessage) {
            state = state.copyWith(driver: message.data);
          }
          break;
        default:
          break;
      }
    });

    _errorSubscription = _wsService.errorStream.listen((error) {
      // Only show critical errors, not connection status messages or network errors
      if (!error.contains('WebSocket closed') && 
          !error.contains('connection') &&
          !error.contains('Network is unreachable') &&
          !error.contains('Connection refused')) {
        if (mounted) {
          state = state.copyWith(error: error);
        }
      }
    });

    // Listen to connection status
    _wsService.connectionStream.listen((connected) {
      if (!mounted) return;
      
      if (!connected && _wsService.hasMaxReconnectAttempts) {
        // Only show error if not already showing a network error
        if (state.error == null || 
            (!state.error!.contains('Network is unreachable') && 
             !state.error!.contains('Unable to connect'))) {
          state = state.copyWith(
            error: 'Unable to connect to server. Please check your connection and try again.',
          );
        }
      } else if (connected) {
        // Clear connection-related errors when reconnected
        if (state.error != null && 
            (state.error!.contains('connect') || 
             state.error!.contains('Unable to connect') ||
             state.error!.contains('internet connection'))) {
          state = state.copyWith(error: null);
        }
      }
    });
  }

  void updateLocation(Coordinate location, String geohash) {
    _wsService.sendLocation(location, geohash: geohash);
  }

  void acceptTrip() {
    if (state.requestedTrip == null || state.driver == null) {
      state = state.copyWith(error: 'No trip or driver found');
      return;
    }

    final message = DriverResponseToTripMessage(
      DriverResponseData(
        tripID: state.requestedTrip!.id,
        riderID: state.requestedTrip!.userID,
        driver: state.driver!,
      ),
      TripEvents.driverTripAccept,
    );

    _wsService.sendMessage(message);
    state = state.copyWith(tripStatus: TripEvents.driverTripAccept);
  }

  void declineTrip() {
    if (state.requestedTrip == null || state.driver == null) {
      state = state.copyWith(error: 'No trip or driver found');
      return;
    }

    final message = DriverResponseToTripMessage(
      DriverResponseData(
        tripID: state.requestedTrip!.id,
        riderID: state.requestedTrip!.userID,
        driver: state.driver!,
      ),
      TripEvents.driverTripDecline,
    );

    _wsService.sendMessage(message);
    state = state.copyWith(
      tripStatus: TripEvents.driverTripDecline,
      requestedTrip: null,
    );
  }

  void resetTripStatus() {
    state = state.copyWith(
      tripStatus: null,
      requestedTrip: null,
    );
  }

  void reconnect() {
    _wsService.reconnect();
  }

  @override
  void dispose() {
    _disposed = true;
    _messageSubscription?.cancel();
    _errorSubscription?.cancel();
    _wsService.disconnect();
    super.dispose();
  }
}

final driverProvider = StateNotifierProvider.family<DriverNotifier, DriverState,
    DriverProviderParams>((ref, params) {
  final wsService = WebSocketService();
  return DriverNotifier(wsService, params.userId, params.packageSlug);
});

class DriverProviderParams {
  final String userId;
  final CarPackageSlug packageSlug;

  DriverProviderParams({required this.userId, required this.packageSlug});
}

