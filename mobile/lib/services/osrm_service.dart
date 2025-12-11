import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/types.dart';

/// OSRM Route Service
/// Documentation: https://project-osrm.org/docs/v5.24.0/api/#route-service
class OSRMService {
  // Default OSRM server (can be overridden)
  static const String defaultOSRMServer = 'https://router.project-osrm.org';
  
  final String serverUrl;
  
  OSRMService({String? serverUrl}) 
      : serverUrl = serverUrl ?? defaultOSRMServer;

  /// Get route between coordinates using OSRM
  /// 
  /// [coordinates] - List of coordinates in order: [pickup, destination, ...]
  /// [profile] - Transportation mode: 'driving', 'walking', 'cycling' (default: 'driving')
  /// [overview] - Route overview: 'full', 'simplified', 'false' (default: 'full')
  /// [geometries] - Geometry format: 'polyline', 'polyline6', 'geojson' (default: 'geojson')
  /// 
  /// Returns OSRM route response with geometry, distance, and duration
  Future<OSRMRouteResponse> getRoute({
    required List<Coordinate> coordinates,
    String profile = 'driving',
    String overview = 'full',
    String geometries = 'geojson',
  }) async {
    if (coordinates.length < 2) {
      throw ArgumentError('At least 2 coordinates are required');
    }

    // Format coordinates as: longitude,latitude;longitude,latitude
    final coordsString = coordinates
        .map((coord) => '${coord.longitude},${coord.latitude}')
        .join(';');

    final uri = Uri.parse(
      '$serverUrl/route/v1/$profile/$coordsString'
      '?overview=$overview'
      '&geometries=$geometries'
      '&steps=false'
      '&alternatives=false',
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (jsonData['code'] == 'Ok') {
          return OSRMRouteResponse.fromJson(jsonData);
        } else {
          throw Exception('OSRM error: ${jsonData['message'] ?? jsonData['code']}');
        }
      } else {
        throw Exception('OSRM request failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get route from OSRM: $e');
    }
  }

  /// Get route between pickup and destination
  Future<OSRMRouteResponse> getRouteBetween({
    required Coordinate pickup,
    required Coordinate destination,
    String profile = 'driving',
  }) {
    return getRoute(
      coordinates: [pickup, destination],
      profile: profile,
    );
  }
}

/// OSRM Route Response Model
class OSRMRouteResponse {
  final String code;
  final String? message;
  final List<OSRMRoute> routes;
  final List<OSRMWaypoint> waypoints;

  OSRMRouteResponse({
    required this.code,
    this.message,
    required this.routes,
    required this.waypoints,
  });

  factory OSRMRouteResponse.fromJson(Map<String, dynamic> json) {
    return OSRMRouteResponse(
      code: json['code'] ?? '',
      message: json['message'],
      routes: (json['routes'] as List<dynamic>?)
              ?.map((r) => OSRMRoute.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      waypoints: (json['waypoints'] as List<dynamic>?)
              ?.map((w) => OSRMWaypoint.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Convert OSRM route to app's Coordinate list format
  List<Coordinate> toCoordinateList() {
    if (routes.isEmpty) return [];
    
    final route = routes.first;
    if (route.geometry.coordinates.isEmpty) return [];
    
    // OSRM returns coordinates as [longitude, latitude] in GeoJSON format
    return route.geometry.coordinates
        .map((coord) => Coordinate(
              latitude: (coord[1] as num).toDouble(),
              longitude: (coord[0] as num).toDouble(),
            ))
        .toList();
  }

  /// Get distance in meters
  double get distance => routes.isNotEmpty ? routes.first.distance : 0.0;

  /// Get duration in seconds
  int get duration => routes.isNotEmpty ? routes.first.duration.round() : 0;
}

class OSRMRoute {
  final double distance; // in meters
  final double duration; // in seconds
  final OSRMGeometry geometry;

  OSRMRoute({
    required this.distance,
    required this.duration,
    required this.geometry,
  });

  factory OSRMRoute.fromJson(Map<String, dynamic> json) {
    return OSRMRoute(
      distance: (json['distance'] ?? 0).toDouble(),
      duration: (json['duration'] ?? 0).toDouble(),
      geometry: OSRMGeometry.fromJson(json['geometry'] as Map<String, dynamic>),
    );
  }
}

class OSRMGeometry {
  final List<List<dynamic>> coordinates; // [[lon, lat], [lon, lat], ...]
  final String type;

  OSRMGeometry({
    required this.coordinates,
    required this.type,
  });

  factory OSRMGeometry.fromJson(Map<String, dynamic> json) {
    return OSRMGeometry(
      coordinates: (json['coordinates'] as List<dynamic>?)
              ?.map((c) => c as List<dynamic>)
              .toList() ??
          [],
      type: json['type'] ?? 'LineString',
    );
  }
}

class OSRMWaypoint {
  final List<double> location; // [longitude, latitude]
  final String? name;
  final double? distance;

  OSRMWaypoint({
    required this.location,
    this.name,
    this.distance,
  });

  factory OSRMWaypoint.fromJson(Map<String, dynamic> json) {
    return OSRMWaypoint(
      location: (json['location'] as List<dynamic>?)
              ?.map((l) => (l as num).toDouble())
              .toList()
              .cast<double>() ??
          <double>[],
      name: json['name'],
      distance: json['distance']?.toDouble(),
    );
  }
}
