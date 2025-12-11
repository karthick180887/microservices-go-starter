import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contracts.dart';
import '../models/types.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import 'dart:async';

class RiderState {
  final List<Driver> drivers;
  final TripEvents? tripStatus;
  final PaymentSessionData? paymentSession;
  final Driver? assignedDriver;
  final TripPreview? tripPreview;
  final String? error;
  final bool isLoadingPreview;

  RiderState({
    this.drivers = const [],
    this.tripStatus,
    this.paymentSession,
    this.assignedDriver,
    this.tripPreview,
    this.error,
    this.isLoadingPreview = false,
  });

  RiderState copyWith({
    List<Driver>? drivers,
    TripEvents? tripStatus,
    PaymentSessionData? paymentSession,
    Driver? assignedDriver,
    TripPreview? tripPreview,
    String? error,
    bool? isLoadingPreview,
  }) {
    return RiderState(
      drivers: drivers ?? this.drivers,
      tripStatus: tripStatus ?? this.tripStatus,
      paymentSession: paymentSession ?? this.paymentSession,
      assignedDriver: assignedDriver ?? this.assignedDriver,
      tripPreview: tripPreview ?? this.tripPreview,
      error: error ?? this.error,
      isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
    );
  }
}

class RiderNotifier extends StateNotifier<RiderState> {
  final WebSocketService _wsService;
  final ApiService _apiService;
  final String userId;
  StreamSubscription<ServerWsMessage>? _messageSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _disposed = false;
  Coordinate? _initialLocation;
  Coordinate? _lastPickupLocation;
  Coordinate? _lastDestinationLocation;

  RiderNotifier(this._wsService, this._apiService, this.userId)
      : super(RiderState()) {
    _connect();
  }
  
  @override
  bool get mounted => !_disposed;

  void setInitialLocation(Coordinate location) {
    _initialLocation = location;
    // If already connected, send location immediately
    if (_wsService.isConnected) {
      _wsService.sendLocation(location);
    }
  }

  void _connect() {
    // Send initial location on connection open (matches web app behavior)
    _wsService.connect(
      BackendEndpoints.wsRiders.value,
      queryParams: {'userID': userId},
      initialLocation: _initialLocation,
    );

    _messageSubscription = _wsService.messageStream.listen((message) {
      if (!mounted) return;
      
      switch (message.type) {
        case TripEvents.driverLocation:
          if (message is DriverLocationMessage) {
            // Only update if drivers actually changed
            final newDrivers = message.data;
            if (state.drivers.length != newDrivers.length ||
                !_driversEqual(state.drivers, newDrivers)) {
              state = state.copyWith(drivers: newDrivers);
            }
          }
          break;
        case TripEvents.paymentSessionCreated:
          if (message is PaymentSessionCreatedMessage) {
            // Keep the current trip status (e.g., driverAssigned) and just add payment session
            // This allows showing both driver info and payment button
            state = state.copyWith(
              paymentSession: message.data,
              // Only update tripStatus if not already in a more specific state
              tripStatus: state.tripStatus ?? message.type,
            );
            print('RiderProvider: Payment session created, amount: ${message.data.amount} ${message.data.currency}');
          }
          break;
        case TripEvents.driverAssigned:
          if (message is DriverAssignedMessage) {
            print('RiderProvider: Received driverAssigned message, driver: ${message.data.driver?.name ?? 'null'}');
            state = state.copyWith(
              assignedDriver: message.data.driver,
              tripStatus: message.type,
            );
            print('RiderProvider: Updated state with driver: ${state.assignedDriver?.name ?? 'null'}, status: ${state.tripStatus}');
          } else {
            print('RiderProvider: driverAssigned message is not DriverAssignedMessage, type: ${message.runtimeType}');
          }
          break;
        case TripEvents.created:
          state = state.copyWith(tripStatus: message.type);
          break;
        case TripEvents.noDriversFound:
          state = state.copyWith(tripStatus: message.type);
          break;
        default:
          break;
      }
    });

    _errorSubscription = _wsService.errorStream.listen((error) {
      // Only show critical errors after max reconnect attempts
      // Don't show errors during reconnection attempts
      if (_wsService.hasMaxReconnectAttempts) {
        if (mounted) {
          state = state.copyWith(error: error);
        }
      }
      // Silently handle errors during reconnection attempts
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
        // Clear connection-related errors when reconnected, but only if not loading preview
        if (state.error != null && 
            !state.isLoadingPreview &&
            (state.error!.contains('connect') || 
             state.error!.contains('Unable to connect') ||
             state.error!.contains('internet connection'))) {
          state = state.copyWith(error: null);
        }
      }
    });
  }

  Future<void> previewTrip(Coordinate pickup, Coordinate destination) async {
    // Store locations for retry
    _lastPickupLocation = pickup;
    _lastDestinationLocation = destination;
    
    // Clear any previous errors and set loading state immediately
    print('Preview trip: Setting loading state to true');
    state = state.copyWith(error: null, isLoadingPreview: true);
    
    try {
      print('Preview trip: Making API call');
      final response = await _apiService.previewTrip(HTTPTripPreviewRequest(
        userID: userId,
        pickup: pickup,
        destination: destination,
      ));

      print('Preview trip: API call successful');
      // Convert route coordinates to list format
      final route = response.route.geometry.isNotEmpty
          ? response.route.geometry[0].coordinates
          : <Coordinate>[];
      
      final tripPreview = TripPreview(
        tripID: '',
        route: route,
        rideFares: response.rideFares,
        duration: response.route.duration,
        distance: response.route.distance,
      );

      state = state.copyWith(tripPreview: tripPreview, error: null, isLoadingPreview: false);
    } catch (e) {
      // Extract user-friendly error message
      print('Preview trip: Error occurred - $e');
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(error: errorMessage, isLoadingPreview: false);
    }
  }
  
  void setLoadingState(bool loading) {
    state = state.copyWith(isLoadingPreview: loading);
  }

  Future<void> retryPreviewTrip() async {
    if (_lastPickupLocation != null && _lastDestinationLocation != null) {
      await previewTrip(_lastPickupLocation!, _lastDestinationLocation!);
    }
  }

  Future<void> startTrip(RouteFare fare) async {
    // Clear any previous errors
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
    
    try {
      final response = await _apiService.startTrip(HTTPTripStartRequest(
        rideFareID: fare.id,
        userID: userId,
      ));

      if (state.tripPreview != null) {
        // Update trip preview with trip ID and set status to created
        // The WebSocket will update this status when driver is assigned
        state = state.copyWith(
          tripPreview: TripPreview(
            tripID: response.tripID,
            route: state.tripPreview!.route,
            rideFares: state.tripPreview!.rideFares,
            duration: state.tripPreview!.duration,
            distance: state.tripPreview!.distance,
          ),
          tripStatus: TripEvents.created, // Set status immediately
          error: null,
        );
      }
    } catch (e) {
      // Extract user-friendly error message
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(error: errorMessage);
    }
  }

  void resetTripStatus() {
    state = state.copyWith(
      tripStatus: null,
      paymentSession: null,
      tripPreview: null,
      isLoadingPreview: false,
    );
  }

  void reconnect() {
    _wsService.reconnect();
    // Also retry preview trip if there was a previous attempt
    if (_lastPickupLocation != null && _lastDestinationLocation != null) {
      retryPreviewTrip();
    }
  }

  bool _driversEqual(List<Driver> a, List<Driver> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].location.latitude != b[i].location.latitude ||
          a[i].location.longitude != b[i].location.longitude) {
        return false;
      }
    }
    return true;
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

final riderProvider = StateNotifierProvider.family<RiderNotifier, RiderState,
    String>((ref, userId) {
  final wsService = WebSocketService();
  final apiService = ApiService();
  return RiderNotifier(wsService, apiService, userId);
});
