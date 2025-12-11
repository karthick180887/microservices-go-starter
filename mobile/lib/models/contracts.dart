import 'types.dart';

enum TripEvents {
  noDriversFound('trip.event.no_drivers_found'),
  driverAssigned('trip.event.driver_assigned'),
  completed('trip.event.completed'),
  cancelled('trip.event.cancelled'),
  created('trip.event.created'),
  driverLocation('driver.cmd.location'),
  driverTripRequest('driver.cmd.trip_request'),
  driverTripAccept('driver.cmd.trip_accept'),
  driverTripDecline('driver.cmd.trip_decline'),
  driverRegister('driver.cmd.register'),
  paymentSessionCreated('payment.event.session_created');

  final String value;
  const TripEvents(this.value);

  static TripEvents fromString(String value) {
    for (var event in TripEvents.values) {
      if (event.value == value) {
        return event;
      }
    }
    throw ArgumentError('Unknown trip event: $value');
  }
}

enum BackendEndpoints {
  previewTrip('/trip/preview'),
  startTrip('/trip/start'),
  wsDrivers('/drivers'),
  wsRiders('/riders');

  final String value;
  const BackendEndpoints(this.value);
}

// Server to Client Messages
abstract class ServerWsMessage {
  final TripEvents type;
  ServerWsMessage(this.type);
}

class DriverLocationMessage extends ServerWsMessage {
  final List<Driver> data;
  DriverLocationMessage(this.data) : super(TripEvents.driverLocation);
}

class DriverAssignedMessage extends ServerWsMessage {
  final Trip data;
  DriverAssignedMessage(this.data) : super(TripEvents.driverAssigned);
}

class TripCreatedMessage extends ServerWsMessage {
  final Trip data;
  TripCreatedMessage(this.data) : super(TripEvents.created);
}

class NoDriversFoundMessage extends ServerWsMessage {
  NoDriversFoundMessage() : super(TripEvents.noDriversFound);
}

class PaymentSessionCreatedMessage extends ServerWsMessage {
  final PaymentSessionData data;
  PaymentSessionCreatedMessage(this.data)
      : super(TripEvents.paymentSessionCreated);
}

class DriverTripRequestMessage extends ServerWsMessage {
  final Trip data;
  DriverTripRequestMessage(this.data) : super(TripEvents.driverTripRequest);
}

class DriverRegisterMessage extends ServerWsMessage {
  final Driver data;
  DriverRegisterMessage(this.data) : super(TripEvents.driverRegister);
}

// Client to Server Messages
abstract class ClientWsMessage {
  final TripEvents type;
  ClientWsMessage(this.type);
}

class DriverResponseToTripMessage extends ClientWsMessage {
  final DriverResponseData data;
  DriverResponseToTripMessage(this.data, TripEvents type) : super(type);
}

class PaymentSessionData {
  final String tripID;
  final String sessionID;
  final double amount;
  final String currency;

  PaymentSessionData({
    required this.tripID,
    required this.sessionID,
    required this.amount,
    required this.currency,
  });

  factory PaymentSessionData.fromJson(Map<String, dynamic> json) =>
      PaymentSessionData(
        tripID: json['tripID'] ?? '',
        sessionID: json['sessionID'] ?? '',
        amount: (json['amount'] ?? 0).toDouble(),
        currency: json['currency'] ?? 'USD',
      );
}

class DriverResponseData {
  final String tripID;
  final String riderID;
  final Driver driver;

  DriverResponseData({
    required this.tripID,
    required this.riderID,
    required this.driver,
  });

  Map<String, dynamic> toJson() => {
        'tripID': tripID,
        'riderID': riderID,
        'driver': driver.toJson(),
      };
}

extension DriverToJson on Driver {
  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location.toJson(),
        'geohash': geohash,
        'name': name,
        'profilePicture': profilePicture,
        'carPlate': carPlate,
      };
}

// HTTP Request/Response Types
class HTTPTripPreviewRequest {
  final String userID;
  final Coordinate pickup;
  final Coordinate destination;

  HTTPTripPreviewRequest({
    required this.userID,
    required this.pickup,
    required this.destination,
  });

  Map<String, dynamic> toJson() => {
        'userID': userID,
        'pickup': pickup.toJson(),
        'destination': destination.toJson(),
      };
}

class HTTPTripPreviewResponse {
  final Route route;
  final List<RouteFare> rideFares;

  HTTPTripPreviewResponse({
    required this.route,
    required this.rideFares,
  });

  factory HTTPTripPreviewResponse.fromJson(Map<String, dynamic> json) =>
      HTTPTripPreviewResponse(
        route: json['route'] != null
            ? Route.fromJson(json['route'] as Map<String, dynamic>)
            : Route(geometry: [], duration: 0, distance: 0.0),
        rideFares: (json['rideFares'] as List<dynamic>?)
                ?.map((f) => RouteFare.fromJson(f as Map<String, dynamic>))
                .toList() ??
            [],
      );
  
  // Named constructor for creating from Route directly (for OSRM)
  HTTPTripPreviewResponse.fromRoute({
    required this.route,
    List<RouteFare>? rideFares,
  }) : rideFares = rideFares ?? [];
}

class HTTPTripStartRequest {
  final String rideFareID;
  final String userID;

  HTTPTripStartRequest({
    required this.rideFareID,
    required this.userID,
  });

  Map<String, dynamic> toJson() => {
        'rideFareID': rideFareID,
        'userID': userID,
      };
}

class HTTPTripStartResponse {
  final String tripID;

  HTTPTripStartResponse({required this.tripID});

  factory HTTPTripStartResponse.fromJson(Map<String, dynamic> json) =>
      HTTPTripStartResponse(tripID: json['tripID'] ?? '');
}
