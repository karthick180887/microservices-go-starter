import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import '../models/types.dart';

class LocationAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final Function(Placemark) onLocationSelected;
  final Function(Coordinate) onCoordinateSelected;

  const LocationAutocomplete({
    super.key,
    required this.controller,
    required this.onLocationSelected,
    required this.onCoordinateSelected,
  });

  @override
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  List<Placemark> _suggestions = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _debounceTimer?.cancel();
    final query = widget.controller.text.trim();

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _searchLocations(query);
    });
  }

  Future<void> _searchLocations(String query) async {
    if (query.length < 3) {
      // Don't search for very short queries
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isSearching = false;
        });
      }
      return;
    }

    try {
      List<Location> locations = await locationFromAddress(query);
      List<Placemark> placemarks = [];

      // Limit to 3 results for better performance
      for (var location in locations.take(3)) {
        try {
          List<Placemark> places = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );
          if (places.isNotEmpty) {
            placemarks.add(places.first);
          }
        } catch (e) {
          // Continue with next location
        }
      }

      if (mounted) {
        setState(() {
          _suggestions = placemarks;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isSearching = false;
        });
      }
    }
  }

  String _formatAddress(Placemark place) {
    final parts = <String>[];
    if (place.street != null && place.street!.isNotEmpty) {
      parts.add(place.street!);
    }
    if (place.locality != null && place.locality!.isNotEmpty) {
      parts.add(place.locality!);
    }
    if (place.administrativeArea != null &&
        place.administrativeArea!.isNotEmpty) {
      parts.add(place.administrativeArea!);
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.text.isEmpty || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            ...List.generate(
              _suggestions.length,
              (index) {
                final place = _suggestions[index];
                return InkWell(
                  onTap: () async {
                    // Dismiss keyboard when selecting a suggestion
                    FocusScope.of(context).unfocus();
                    
                    widget.controller.text = _formatAddress(place);
                    widget.onLocationSelected(place);
                    
                    // Get coordinates for the selected place
                    try {
                      List<Location> locations = await locationFromAddress(_formatAddress(place));
                      if (locations.isNotEmpty) {
                        widget.onCoordinateSelected(Coordinate(
                          latitude: locations.first.latitude,
                          longitude: locations.first.longitude,
                        ));
                      }
                    } catch (e) {
                      // Handle error silently
                    }
                    
                    if (mounted) {
                      setState(() {
                        _suggestions = [];
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatAddress(place),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (place.country != null)
                                Text(
                                  place.country!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }
}
