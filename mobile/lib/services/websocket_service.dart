import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants.dart';
import '../models/contracts.dart';
import '../models/types.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  final StreamController<ServerWsMessage> _messageController =
      StreamController<ServerWsMessage>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<ServerWsMessage> get messageStream => _messageController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  Timer? _reconnectTimer;
  String? _endpoint;
  Map<String, String>? _queryParams;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);

  bool get isConnected => _isConnected && _channel != null;
  int get reconnectAttempts => _reconnectAttempts;
  bool get hasMaxReconnectAttempts => _reconnectAttempts >= _maxReconnectAttempts;

  void connect(
    String endpoint, {
    Map<String, String>? queryParams,
    Coordinate? initialLocation,
    String? geohash,
  }) {
    _endpoint = endpoint;
    _queryParams = queryParams;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _initialLocation = initialLocation;
    _initialGeohash = geohash;
    _connectInternal();
  }

  Coordinate? _initialLocation;
  String? _initialGeohash;

  void _connectInternal() {
    if (_isConnecting || _isConnected) return;
    
    _isConnecting = true;
    final uri = Uri.parse('${Constants.websocketUrl}$_endpoint');
    final uriWithParams = _queryParams != null
        ? uri.replace(queryParameters: _queryParams)
        : uri;

    // Debug: Log the connection URL
    print('WebSocket connecting to: $uriWithParams');

    Timer? connectionTimeout;
    bool connectionEstablished = false;
    bool hasErrorOccurred = false;

    // Use runZoned to catch any unhandled async errors
    runZonedGuarded(() {
      try {
        // Connect to WebSocket - this may throw synchronously or fail asynchronously
        _channel = WebSocketChannel.connect(uriWithParams);
        
        // Set up stream listener with error handling
        _streamSubscription = _channel!.stream.listen(
          (message) {
            // First message received means connection is established
            if (!connectionEstablished && !hasErrorOccurred) {
              connectionEstablished = true;
              connectionTimeout?.cancel();
              print('WebSocket received first message - connection confirmed');
              _markAsConnected();
            }
            
            try {
              final json = jsonDecode(message as String);
              final serverMessage = _parseServerMessage(json);
              if (serverMessage != null) {
                _messageController.add(serverMessage);
              }
            } catch (e) {
              // Don't treat parsing errors as critical connection errors
              // Silently handle parsing errors
            }
          },
          onError: (error) {
            hasErrorOccurred = true;
            connectionTimeout?.cancel();
            print('WebSocket stream error: $error');
            _handleConnectionError(error);
          },
          onDone: () {
            hasErrorOccurred = true;
            connectionTimeout?.cancel();
            print('WebSocket stream done (closed)');
            _handleConnectionClosed();
          },
          cancelOnError: false,
        );

        // Set a connection timeout - if no error and no message after 5 seconds, 
        // try to verify connection or fail it
        connectionTimeout = Timer(const Duration(seconds: 5), () {
          if (!connectionEstablished && !hasErrorOccurred && _channel != null && _shouldReconnect) {
            // Check if we can write to the channel (connection is likely established)
            try {
              // Try to send a ping or check connection state
              // If we haven't received an error, assume connection is good
              // (backend might not send initial message)
              print('WebSocket connection timeout - assuming connected (no errors received)');
              connectionEstablished = true;
              _markAsConnected();
            } catch (e) {
              // Connection failed
              print('WebSocket connection timeout - connection failed: $e');
              hasErrorOccurred = true;
              _handleConnectionError('Connection timeout: Unable to establish WebSocket connection');
            }
          }
        });
      } catch (e, stackTrace) {
        hasErrorOccurred = true;
        connectionTimeout?.cancel();
        print('WebSocket connection exception: $e');
        _handleConnectionException(e, stackTrace);
      }
    }, (error, stackTrace) {
      // Catch any unhandled async errors
      hasErrorOccurred = true;
      connectionTimeout?.cancel();
      print('WebSocket unhandled error: $error');
      _handleConnectionException(error, stackTrace);
    });
  }

  void _markAsConnected() {
    if (_isConnected) return; // Already connected
    
    print('WebSocket connected successfully');
    _isConnecting = false;
    _isConnected = true;
    _reconnectAttempts = 0;
    _connectionController.add(true);
    
    // Clear any previous connection errors
    // Note: We don't clear all errors here, only connection-related ones
    // Other errors (like API errors) should persist
    
    // Send initial location on connection open (like web app)
    _sendInitialLocation();
  }

  void _handleConnectionError(dynamic error) {
    print('WebSocket connection error: $error');
    _isConnecting = false;
    _isConnected = false;
    _connectionController.add(false);
    
    // Clean up failed connection
    _streamSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    
    final errorString = error.toString();
    final isNetworkError = error is SocketException ||
        errorString.contains('Network is unreachable') ||
        errorString.contains('Connection refused') ||
        errorString.contains('SocketException') ||
        errorString.contains('OS Error: Network is unreachable') ||
        errorString.contains('Failed host lookup') ||
        errorString.contains('Connection timed out');
    
    // Handle network errors
    if (isNetworkError) {
      if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
        print('Scheduling reconnect attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts');
        _scheduleReconnect();
      } else if (_reconnectAttempts >= _maxReconnectAttempts) {
        // Report error after max reconnect attempts with helpful message
        print('Max reconnect attempts reached. Reporting error to user.');
        final serverUrl = '${Constants.websocketUrl}$_endpoint';
        _errorController.add(
          'Unable to connect to server at $serverUrl.\n\n'
          'Please check:\n'
          '• Server is running\n'
          '• Correct IP address (currently: ${Constants.websocketUrl.split('://')[1].split(':')[0]})\n'
          '• Device and server are on the same network\n'
          '• Firewall is not blocking the connection'
        );
      }
      return;
    }
    
    // For other errors, try to reconnect or report
    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      _errorController.add('WebSocket connection error: $error');
    }
  }

  void _handleConnectionClosed() {
    _isConnecting = false;
    _isConnected = false;
    _connectionController.add(false);
    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  void _handleConnectionException(dynamic e, StackTrace stackTrace) {
    print('WebSocket connection exception: $e');
    _isConnecting = false;
    _isConnected = false;
    _connectionController.add(false);
    
    // Clean up failed connection
    _streamSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    
    final errorString = e.toString();
    final isNetworkError = e is SocketException ||
        errorString.contains('Network is unreachable') ||
        errorString.contains('Connection refused') ||
        errorString.contains('SocketException') ||
        errorString.contains('OS Error: Network is unreachable') ||
        errorString.contains('Failed host lookup') ||
        errorString.contains('Connection timed out');
    
    // Handle network errors
    if (isNetworkError) {
      if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
        print('Scheduling reconnect attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts');
        _scheduleReconnect();
      } else if (_reconnectAttempts >= _maxReconnectAttempts) {
        // Report error after max reconnect attempts with helpful message
        final serverUrl = '${Constants.websocketUrl}$_endpoint';
        final urlParts = Constants.websocketUrl.split('://');
        final hostPart = urlParts.length > 1 ? urlParts[1].split(':')[0] : 'unknown';
        _errorController.add(
          'Unable to connect to server at $serverUrl.\n\n'
          'Please check:\n'
          '• Server is running on port 8081\n'
          '• Correct IP address (currently: $hostPart)\n'
          '• Device and server are on the same network\n'
          '• Firewall is not blocking the connection\n'
          '• If using Android emulator, use 10.0.2.2 instead of localhost'
        );
      }
      return;
    }
    
    // For other errors, try to reconnect or report
    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      _errorController.add('Failed to connect: $e');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(
      seconds: (_initialReconnectDelay.inSeconds * _reconnectAttempts)
          .clamp(2, 30),
    );
    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !_isConnected) {
        // Wrap in try-catch to prevent unhandled exceptions
        try {
          _connectInternal();
        } catch (e, stackTrace) {
          // Silently handle exceptions - they'll be caught by _connectInternal
          _handleConnectionException(e, stackTrace);
        }
      }
    });
  }

  void reconnect() {
    _reconnectAttempts = 0;
    disconnect();
    Future.delayed(const Duration(seconds: 1), () {
      if (_endpoint != null) {
        _connectInternal();
      }
    });
  }

  void sendMessage(ClientWsMessage message) {
    if (isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': message.type.value,
          'data': _messageToJson(message),
        }));
      } catch (e) {
        _errorController.add('Failed to send message: $e');
      }
    } else {
      _errorController.add('Cannot send message: WebSocket not connected');
    }
  }

  void _sendInitialLocation() {
    if (_initialLocation != null && isConnected && _channel != null) {
      try {
        final data = <String, dynamic>{
          'location': _initialLocation!.toJson(),
        };
        
        if (_initialGeohash != null) {
          data['geohash'] = _initialGeohash;
        }
        
        _channel!.sink.add(jsonEncode({
          'type': TripEvents.driverLocation.value,
          'data': data,
        }));
      } catch (e) {
        // Silently handle - initial location send is not critical
      }
    }
  }

  void sendLocation(Coordinate location, {String? geohash}) {
    if (isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': TripEvents.driverLocation.value,
          'data': {
            'location': location.toJson(),
            if (geohash != null) 'geohash': geohash,
          },
        }));
      } catch (e) {
        _errorController.add('Failed to send location: $e');
      }
    }
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _streamSubscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
  }

  ServerWsMessage? _parseServerMessage(Map<String, dynamic> json) {
    final typeString = json['type'] as String?;
    if (typeString == null) return null;

    try {
      final type = TripEvents.fromString(typeString);
      final data = json['data'];

      switch (type) {
        case TripEvents.driverLocation:
          final drivers = (data as List<dynamic>?)
                  ?.map((d) => Driver.fromJson(d as Map<String, dynamic>))
                  .toList() ??
              [];
          return DriverLocationMessage(drivers);

        case TripEvents.driverAssigned:
          print('WebSocket: Parsing driverAssigned message, data: $data');
          try {
            final trip = Trip.fromJson(data as Map<String, dynamic>);
            print('WebSocket: Parsed trip, driver: ${trip.driver?.name ?? 'null'}, tripID: ${trip.id}');
            return DriverAssignedMessage(trip);
          } catch (e, stackTrace) {
            print('WebSocket: Error parsing driverAssigned message: $e');
            print('WebSocket: Stack trace: $stackTrace');
            rethrow;
          }

        case TripEvents.created:
          return TripCreatedMessage(
              Trip.fromJson(data as Map<String, dynamic>));

        case TripEvents.noDriversFound:
          return NoDriversFoundMessage();

        case TripEvents.paymentSessionCreated:
          return PaymentSessionCreatedMessage(
              PaymentSessionData.fromJson(data as Map<String, dynamic>));

        case TripEvents.driverTripRequest:
          return DriverTripRequestMessage(
              Trip.fromJson(data as Map<String, dynamic>));

        case TripEvents.driverRegister:
          return DriverRegisterMessage(
              Driver.fromJson(data as Map<String, dynamic>));

        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _messageToJson(ClientWsMessage message) {
    if (message is DriverResponseToTripMessage) {
      return message.data.toJson();
    }
    return {};
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _errorController.close();
    _connectionController.close();
  }
}

