import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import '../models/types.dart';
import '../providers/rider_provider.dart';
import '../widgets/rider_trip_overview.dart';
import '../widgets/location_autocomplete.dart';
import 'dart:async';

class RiderMapScreen extends ConsumerStatefulWidget {
  final String userId;

  const RiderMapScreen({super.key, required this.userId});

  @override
  ConsumerState<RiderMapScreen> createState() => _RiderMapScreenState();
}

class _RiderMapScreenState extends ConsumerState<RiderMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  Coordinate? _pickupLocation;
  Coordinate? _destinationLocation;
  bool _isGettingLocation = false;
  bool _showBottomSheet = false;
  Timer? _markerUpdateTimer;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(riderProvider(widget.userId).notifier);
      // Set initial location for WebSocket (will be sent on connection open)
      if (_pickupLocation != null) {
        notifier.setInitialLocation(_pickupLocation!);
      }
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
      
      _pickupLocation = newLocation;
      
      // Update initial location in provider for WebSocket
      final notifier = ref.read(riderProvider(widget.userId).notifier);
      notifier.setInitialLocation(newLocation);

      // Get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          _pickupController.text =
              '${place.street ?? ''} ${place.locality ?? ''} ${place.administrativeArea ?? ''}'
                  .trim();
          if (_pickupController.text.isEmpty) {
            _pickupController.text = 'Current Location';
          }
        } else {
          _pickupController.text = 'Current Location';
        }
      } catch (e) {
        _pickupController.text = 'Current Location';
      }

      // Move camera to current location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
          ),
        );
      }

      setState(() => _isGettingLocation = false);
    } catch (e) {
      // Fallback to default location
      _pickupLocation = Coordinate(
        latitude: Constants.defaultLatitude,
        longitude: Constants.defaultLongitude,
      );
      _pickupController.text = 'Current Location';
      setState(() => _isGettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch only specific parts of state to reduce rebuilds
    final tripPreview = ref.watch(
      riderProvider(widget.userId).select((state) => state.tripPreview),
    );
    final drivers = ref.watch(
      riderProvider(widget.userId).select((state) => state.drivers),
    );
    final tripStatus = ref.watch(
      riderProvider(widget.userId).select((state) => state.tripStatus),
    );
    final error = ref.watch(
      riderProvider(widget.userId).select((state) => state.error),
    );
    final isLoadingPreview = ref.watch(
      riderProvider(widget.userId).select((state) => state.isLoadingPreview),
    );

    // Debounce marker updates to avoid excessive rebuilds
    _markerUpdateTimer?.cancel();
    _markerUpdateTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _updateMarkers(drivers, tripPreview);
      }
    });

    return Scaffold(
        body: Stack(
          children: [
          // Full screen map - memoized to prevent unnecessary rebuilds
          _buildGoogleMap(drivers, tripPreview),
          // Top location input card (Uber-style)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Location input card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Pickup location
                        _buildLocationRow(
                          icon: Icons.radio_button_checked,
                          iconColor: Colors.black,
                          controller: _pickupController,
                          label: 'Where are you?',
                          enabled: false,
                          onTap: _getCurrentLocation,
                          isLoading: _isGettingLocation,
                        ),
                        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                        // Destination location - editable
                        _buildEditableLocationRow(
                          icon: Icons.location_on,
                          iconColor: Colors.red,
                          controller: _destinationController,
                          label: 'Where to?',
                        ),
                      ],
                    ),
                  ),
                  // Autocomplete suggestions
                  LocationAutocomplete(
                    controller: _destinationController,
                    onLocationSelected: (placemark) async {
                      try {
                        List<Location> locations = await locationFromAddress(
                          '${placemark.street ?? ''} ${placemark.locality ?? ''} ${placemark.administrativeArea ?? ''}',
                        );
                        if (locations.isNotEmpty && mounted) {
                          setState(() {
                            _destinationLocation = Coordinate(
                              latitude: locations.first.latitude,
                              longitude: locations.first.longitude,
                            );
                          });
                        }
                      } catch (e) {
                        // Handle error
                      }
                    },
                    onCoordinateSelected: (coord) {
                      if (mounted) {
                        setState(() {
                          _destinationLocation = coord;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Search button - show if destination text is entered
                  if (_destinationController.text.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isGettingLocation ? null : () {
                          _previewTrip();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isGettingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Search Rides',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Bottom sheet for trip overview - show if opened, loading, has preview, or has error
          if (_showBottomSheet || tripPreview != null || isLoadingPreview || error != null)
            DraggableScrollableSheet(
              initialChildSize: 0.4,
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
                        child: RiderTripOverview(
                          userId: widget.userId,
                          destination: _destinationLocation,
                          onReset: () {
                            if (mounted) {
                              setState(() {
                                _showBottomSheet = false;
                                _destinationController.clear();
                                _destinationLocation = null;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required String label,
    required bool enabled,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      controller.text.isEmpty ? 'Enter address' : controller.text,
                      style: TextStyle(
                        fontSize: 16,
                        color: enabled ? Colors.black : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (enabled && controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  controller.clear();
                  setState(() {
                    _destinationLocation = null;
                  });
                },
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableLocationRow({
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  autofocus: false,
                  focusNode: _destinationFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'Enter address',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                  onChanged: (value) {
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  onSubmitted: (value) {
                    // Dismiss keyboard on submit
                    FocusScope.of(context).unfocus();
                  },
                ),
              ],
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                controller.clear();
                FocusScope.of(context).unfocus();
                if (mounted) {
                  setState(() {
                    _destinationLocation = null;
                  });
                }
              },
              color: Colors.grey,
            ),
        ],
      ),
    );
  }

  Future<void> _previewTrip() async {
    if (_pickupLocation == null) return;

    // Dismiss keyboard before previewing trip
    FocusScope.of(context).unfocus();

    // If destination location is not set but text is entered, try to geocode it
    if (_destinationLocation == null && _destinationController.text.isNotEmpty) {
      try {
        setState(() => _isGettingLocation = true);
        List<Location> locations = await locationFromAddress(_destinationController.text.trim());
        if (locations.isNotEmpty && mounted) {
          setState(() {
            _destinationLocation = Coordinate(
              latitude: locations.first.latitude,
              longitude: locations.first.longitude,
            );
            _isGettingLocation = false;
          });
        } else {
          setState(() => _isGettingLocation = false);
          // Show error if geocoding fails
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not find location for the entered address. Please try again.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      } catch (e) {
        setState(() => _isGettingLocation = false);
        // Show error if geocoding fails
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error finding location: ${e.toString()}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    if (_destinationLocation == null) {
      // Show error if still no destination
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid destination address.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Get notifier reference
    final notifier = ref.read(riderProvider(widget.userId).notifier);
    
    // Set loading state FIRST (synchronously) before opening bottom sheet
    // This ensures the loading state is set before the widget builds
    notifier.setLoadingState(true);
    
    // Open bottom sheet after loading state is set
    if (mounted) {
      setState(() {
        _showBottomSheet = true;
      });
    }
    
    // Make the API call (will update loading state when done)
    await notifier.previewTrip(_pickupLocation!, _destinationLocation!);
  }

  Widget _buildGoogleMap(List<Driver> drivers, TripPreview? tripPreview) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          _pickupLocation?.latitude ?? Constants.defaultLatitude,
          _pickupLocation?.longitude ?? Constants.defaultLongitude,
        ),
        zoom: 15,
      ),
      markers: _markers,
      polylines: _polylines,
      onMapCreated: (controller) {
        _mapController = controller;
        if (mounted) {
          _updateMarkers(drivers, tripPreview);
        }
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapType: MapType.normal,
    );
  }

  void _updateMarkers(List<Driver> drivers, TripPreview? tripPreview) {
    final newMarkers = <Marker>{};
    final newPolylines = <Polyline>{};

    // Pickup location marker
    if (_pickupLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(
            _pickupLocation!.latitude,
            _pickupLocation!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
        ),
      );
    }

    // Driver markers - limit to prevent performance issues
    for (var driver in drivers.take(50)) {
      newMarkers.add(
        Marker(
          markerId: MarkerId(driver.id),
          position: LatLng(
            driver.location.latitude,
            driver.location.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: driver.name,
            snippet: 'Car: ${driver.carPlate}',
          ),
        ),
      );
    }

    // Destination marker
    if (_destinationLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(
            _destinationLocation!.latitude,
            _destinationLocation!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    // Route polyline
    if (tripPreview != null && tripPreview.route.isNotEmpty) {
      // Simplify polyline for performance if too many points
      final routePoints = tripPreview.route.length > 100
          ? _simplifyPolyline(tripPreview.route)
          : tripPreview.route;
      
      newPolylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints
              .map((coord) => LatLng(coord.latitude, coord.longitude))
              .toList(),
          color: Colors.blue,
          width: 5,
        ),
      );

      // Fit bounds to show entire route - only animate once
      if (_mapController != null && 
          routePoints.length > 1 &&
          mounted) {
        final bounds = _calculateBounds(routePoints);
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100),
        );
      }
    }

    // Only update if markers actually changed
    if (!_markersEqual(_markers, newMarkers) || 
        !_polylinesEqual(_polylines, newPolylines)) {
      _markers.clear();
      _markers.addAll(newMarkers);
      _polylines.clear();
      _polylines.addAll(newPolylines);
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Simplify polyline using Douglas-Peucker algorithm (simplified version)
  List<Coordinate> _simplifyPolyline(List<Coordinate> points) {
    if (points.length <= 100) return points;
    
    // Simple decimation: take every Nth point
    final step = (points.length / 100).ceil();
    return List.generate(
      (points.length / step).ceil(),
      (i) => points[i * step],
    );
  }

  bool _markersEqual(Set<Marker> a, Set<Marker> b) {
    if (a.length != b.length) return false;
    for (var marker in a) {
      if (!b.any((m) => m.markerId == marker.markerId &&
          m.position.latitude == marker.position.latitude &&
          m.position.longitude == marker.position.longitude)) {
        return false;
      }
    }
    return true;
  }

  bool _polylinesEqual(Set<Polyline> a, Set<Polyline> b) {
    if (a.length != b.length) return false;
    for (var polyline in a) {
      if (!b.any((p) => p.polylineId == polyline.polylineId &&
          p.points.length == polyline.points.length)) {
        return false;
      }
    }
    return true;
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
    _markerUpdateTimer?.cancel();
    _pickupController.dispose();
    _destinationController.dispose();
    _destinationFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }
}
