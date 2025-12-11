import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/contracts.dart';
import '../models/types.dart';
import 'osrm_service.dart';

class ApiService {
  final String baseUrl;
  final OSRMService? _osrmService;
  final bool useOSRM;

  ApiService({
    String? baseUrl,
    bool useOSRM = false,
    String? osrmServerUrl,
  })  : baseUrl = baseUrl ?? Constants.apiUrl,
        useOSRM = useOSRM,
        _osrmService = useOSRM ? OSRMService(serverUrl: osrmServerUrl) : null;

  Future<HTTPTripPreviewResponse> previewTrip(
      HTTPTripPreviewRequest request) async {
    print('API: Preview trip request to: $baseUrl${BackendEndpoints.previewTrip.value}');
    try {
      // If OSRM is enabled, get route from OSRM first, then get fares from backend
      if (useOSRM && _osrmService != null) {
        try {
          final osrmRoute = await _osrmService!.getRouteBetween(
            pickup: request.pickup,
            destination: request.destination,
          );
          
          // Convert OSRM route to app format
          final routeCoordinates = osrmRoute.toCoordinateList();
          final route = Route(
            geometry: [
              RouteGeometry(coordinates: routeCoordinates),
            ],
            duration: osrmRoute.duration,
            distance: osrmRoute.distance,
          );
          
          // Still get fares from backend
          final response = await http.post(
            Uri.parse('$baseUrl${BackendEndpoints.previewTrip.value}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          ).timeout(const Duration(seconds: 30));

          if (response.statusCode == 200 || response.statusCode == 201) {
            final jsonData = jsonDecode(response.body);
            final responseData = jsonData['data'] as Map<String, dynamic>;
            
            // Use OSRM route but keep backend fares
            return HTTPTripPreviewResponse(
              route: route,
              rideFares: (responseData['rideFares'] as List<dynamic>?)
                      ?.map((f) => RouteFare.fromJson(f as Map<String, dynamic>))
                      .toList() ??
                  [],
            );
          } else {
            // Fallback: use OSRM route only
            return HTTPTripPreviewResponse(
              route: route,
              rideFares: [],
            );
          }
        } catch (e) {
          // Fallback to backend API if OSRM fails
          print('OSRM route failed, falling back to backend: $e');
        }
      }
      
      // Default: use backend API
      final response = await http.post(
        Uri.parse('$baseUrl${BackendEndpoints.previewTrip.value}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = jsonDecode(response.body);
        print('API: Preview trip response: ${response.body}');
        // Handle both wrapped and unwrapped responses
        final responseData = jsonData['data'] ?? jsonData;
        return HTTPTripPreviewResponse.fromJson(responseData as Map<String, dynamic>);
      } else {
        throw Exception('Failed to preview trip: ${response.statusCode}');
      }
    } on SocketException catch (e) {
      // Network unreachable or connection refused
      print('API: Preview trip - SocketException: $e');
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    } on HttpException catch (e) {
      // HTTP protocol errors
      print('API: Preview trip - HttpException: $e');
      throw Exception('Network error occurred. Please try again.');
    } on FormatException catch (e) {
      // JSON parsing errors
      print('API: Preview trip - FormatException: $e');
      throw Exception('Invalid response from server. Please try again.');
    } on TimeoutException catch (e) {
      // Request timeout
      print('API: Preview trip - TimeoutException: $e');
      throw Exception('Request timed out. Please check your connection and try again.');
    } catch (e) {
      // Check if it's a network-related error
      print('API: Preview trip - Other error: $e');
      final errorString = e.toString();
      if (errorString.contains('Network is unreachable') ||
          errorString.contains('Connection refused') ||
          errorString.contains('SocketException') ||
          errorString.contains('OS Error: Network is unreachable') ||
          errorString.contains('Failed host lookup')) {
        throw Exception('Unable to connect to server. Please check your internet connection and try again.');
      }
      // Re-throw other exceptions as-is
      rethrow;
    }
  }

  Future<HTTPTripStartResponse> startTrip(HTTPTripStartRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${BackendEndpoints.startTrip.value}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = jsonDecode(response.body);
        return HTTPTripStartResponse.fromJson(jsonData);
      } else {
        throw Exception('Failed to start trip: ${response.statusCode}');
      }
    } on SocketException catch (e) {
      // Network unreachable or connection refused
      print('API: Start trip - SocketException: $e');
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    } on HttpException catch (e) {
      // HTTP protocol errors
      print('API: Start trip - HttpException: $e');
      throw Exception('Network error occurred. Please try again.');
    } on FormatException catch (e) {
      // JSON parsing errors
      print('API: Start trip - FormatException: $e');
      throw Exception('Invalid response from server. Please try again.');
    } on TimeoutException catch (e) {
      // Request timeout
      print('API: Start trip - TimeoutException: $e');
      throw Exception('Request timed out. Please check your connection and try again.');
    } catch (e) {
      // Check if it's a network-related error
      print('API: Start trip - Other error: $e');
      final errorString = e.toString();
      if (errorString.contains('Network is unreachable') ||
          errorString.contains('Connection refused') ||
          errorString.contains('SocketException') ||
          errorString.contains('OS Error: Network is unreachable') ||
          errorString.contains('Failed host lookup')) {
        throw Exception('Unable to connect to server. Please check your internet connection and try again.');
      }
      // Re-throw other exceptions as-is
      rethrow;
    }
  }
}

