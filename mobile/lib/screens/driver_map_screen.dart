import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../constants.dart';
import '../models/types.dart';
import '../providers/driver_provider.dart';
import '../widgets/driver_trip_overview.dart';
import '../utils/geohash_utils.dart';
import 'dart:async';

class DriverMapScreen extends ConsumerStatefulWidget {
  final String userId;
  final CarPackageSlug packageSlug;

  const DriverMapScreen({
    super.key,
    required this.userId,
    required this.packageSlug,
  });

  @override
  ConsumerState<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends ConsumerState<DriverMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  Coordinate _driverLocation = Coordinate(
    latitude: Constants.defaultLatitude, // Chennai, India
    longitude: Constants.defaultLongitude,
  );
  Timer? _locationUpdateTimer;
  bool _isGettingLocation = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLocationUpdates();
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isGettingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isGettingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isGettingLocation = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newLocation = Coordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      
      setState(() {
        _driverLocation = newLocation;
        _isGettingLocation = false;
      });
      
      // Update initial location in provider for WebSocket
      final notifier = ref.read(driverProvider(DriverProviderParams(
        userId: widget.userId,
        packageSlug: widget.packageSlug,
      )).notifier);
      final geohash = GeohashUtils.encode(
        newLocation.latitude,
        newLocation.longitude,
        7, // precision
      );
      notifier.setInitialLocation(newLocation, geohash);

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(_driverLocation.latitude, _driverLocation.longitude),
          ),
        );
      }
    } catch (e) {
      setState(() => _isGettingLocation = false);
    }
  }

  void _startLocationUpdates() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final geohash = GeohashUtils.encode(
        _driverLocation.latitude,
        _driverLocation.longitude,
        7,
      );
      ref
          .read(driverProvider(DriverProviderParams(
            userId: widget.userId,
            packageSlug: widget.packageSlug,
          )).notifier)
          .updateLocation(_driverLocation, geohash);
    });
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(driverProvider(DriverProviderParams(
      userId: widget.userId,
      packageSlug: widget.packageSlug,
    )));

    _updateMarkers(driverState);

    return Scaffold(
      body: Stack(
        children: [
          // Full screen map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                _driverLocation.latitude,
                _driverLocation.longitude,
              ),
              zoom: 15,
            ),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapType: MapType.normal,
          ),
          // Bottom sheet for trip overview
          DraggableScrollableSheet(
            initialChildSize: driverState.requestedTrip != null ? 0.5 : 0.35,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      spreadRadius: 0,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: DriverTripOverview(
                        userId: widget.userId,
                        packageSlug: widget.packageSlug,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // My location button
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              onPressed: () {
                _getCurrentLocation();
              },
              backgroundColor: Colors.white,
              child: _isGettingLocation
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  void _updateMarkers(DriverState state) {
    _markers.clear();
    _polylines.clear();

    // Driver marker
    _markers.add(
      Marker(
        markerId: MarkerId(widget.userId),
        position: LatLng(
          _driverLocation.latitude,
          _driverLocation.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
    );

    // Trip route markers and polyline
    if (state.requestedTrip != null) {
      final route = state.requestedTrip!.route.geometry[0].coordinates;
      if (route.isNotEmpty) {
        // Start location
        final start = route.first;
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: LatLng(start.latitude, start.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'Pickup Location'),
          ),
        );

        // Destination
        final destination = route.last;
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: LatLng(destination.latitude, destination.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
        );

        // Route polyline
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: route
                .map((coord) => LatLng(coord.latitude, coord.longitude))
                .toList(),
            color: Colors.blue,
            width: 5,
          ),
        );

        // Fit bounds to show entire route
        if (_mapController != null) {
          final bounds = _calculateBounds(route);
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 100),
          );
        }
      }
    }

    setState(() {});
  }

  LatLngBounds _calculateBounds(List<Coordinate> coordinates) {
    double minLat = coordinates.first.latitude;
    double maxLat = coordinates.first.latitude;
    double minLng = coordinates.first.longitude;
    double maxLng = coordinates.first.longitude;

    for (var coord in coordinates) {
      minLat = minLat < coord.latitude ? minLat : coord.latitude;
      maxLat = maxLat > coord.latitude ? maxLat : coord.latitude;
      minLng = minLng < coord.longitude ? minLng : coord.longitude;
      maxLng = maxLng > coord.longitude ? maxLng : coord.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
