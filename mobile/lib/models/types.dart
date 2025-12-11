enum CarPackageSlug {
  sedan,
  suv,
  van,
  luxury;

  String get value {
    switch (this) {
      case CarPackageSlug.sedan:
        return 'sedan';
      case CarPackageSlug.suv:
        return 'suv';
      case CarPackageSlug.van:
        return 'van';
      case CarPackageSlug.luxury:
        return 'luxury';
    }
  }

  static CarPackageSlug fromString(String value) {
    switch (value) {
      case 'sedan':
        return CarPackageSlug.sedan;
      case 'suv':
        return CarPackageSlug.suv;
      case 'van':
        return CarPackageSlug.van;
      case 'luxury':
        return CarPackageSlug.luxury;
      default:
        return CarPackageSlug.sedan;
    }
  }
}

class Coordinate {
  final double latitude;
  final double longitude;

  Coordinate({required this.latitude, required this.longitude});

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory Coordinate.fromJson(Map<String, dynamic> json) => Coordinate(
        latitude: json['latitude']?.toDouble() ?? 0.0,
        longitude: json['longitude']?.toDouble() ?? 0.0,
      );
}

class Route {
  final List<RouteGeometry> geometry;
  final int duration; // in seconds
  final double distance; // in meters

  Route({
    required this.geometry,
    required this.duration,
    required this.distance,
  });

  factory Route.fromJson(Map<String, dynamic> json) {
    // Backend sends duration as double, convert to int
    int duration = 0;
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        duration = json['duration'] as int;
      } else if (json['duration'] is num) {
        duration = (json['duration'] as num).toInt();
      }
    }
    
    double distance = 0.0;
    if (json['distance'] != null) {
      if (json['distance'] is num) {
        distance = json['distance'].toDouble();
      }
    }
    
    // Handle geometry - can be array of RouteGeometry or single geometry
    List<RouteGeometry> geometry = [];
    if (json['geometry'] != null) {
      if (json['geometry'] is List) {
        geometry = (json['geometry'] as List<dynamic>)
            .map((g) {
              if (g is Map<String, dynamic>) {
                return RouteGeometry.fromJson(g);
              }
              return null;
            })
            .whereType<RouteGeometry>()
            .toList();
      }
    }
    
    // If no geometry but has routes array (backend format), extract from first route
    if (geometry.isEmpty && json['routes'] != null && json['routes'] is List) {
      final routes = json['routes'] as List<dynamic>;
      if (routes.isNotEmpty && routes[0] is Map<String, dynamic>) {
        final firstRoute = routes[0] as Map<String, dynamic>;
        // Extract duration and distance from first route if not already set
        if (duration == 0 && firstRoute['duration'] != null) {
          if (firstRoute['duration'] is int) {
            duration = firstRoute['duration'] as int;
          } else if (firstRoute['duration'] is num) {
            duration = (firstRoute['duration'] as num).toInt();
          }
        }
        if (distance == 0.0 && firstRoute['distance'] != null && firstRoute['distance'] is num) {
          distance = (firstRoute['distance'] as num).toDouble();
        }
        // Extract geometry from first route - can be object or array
        if (firstRoute['geometry'] != null) {
          if (firstRoute['geometry'] is Map<String, dynamic>) {
            geometry = [RouteGeometry.fromJson(firstRoute['geometry'] as Map<String, dynamic>)];
          } else if (firstRoute['geometry'] is List) {
            geometry = (firstRoute['geometry'] as List<dynamic>)
                .map((g) {
                  if (g is Map<String, dynamic>) {
                    return RouteGeometry.fromJson(g);
                  }
                  return null;
                })
                .whereType<RouteGeometry>()
                .toList();
          }
        }
      }
    }
    
    return Route(
      geometry: geometry,
      duration: duration,
      distance: distance,
    );
  }
}

class RouteGeometry {
  final List<Coordinate> coordinates;

  RouteGeometry({required this.coordinates});

  factory RouteGeometry.fromJson(Map<String, dynamic> json) {
    List<Coordinate> coordinates = [];
    
    if (json['coordinates'] != null && json['coordinates'] is List) {
      final coordsList = json['coordinates'] as List<dynamic>;
      coordinates = coordsList.map((c) {
        // Handle both formats: {latitude: x, longitude: y} and [longitude, latitude]
        if (c is Map<String, dynamic>) {
          return Coordinate.fromJson(c);
        } else if (c is List && c.length >= 2) {
          // Backend sends [longitude, latitude] arrays
          return Coordinate(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble(),
          );
        }
        return null;
      }).whereType<Coordinate>().toList();
    }
    
    return RouteGeometry(coordinates: coordinates);
  }
}

class RouteFare {
  final String id;
  final CarPackageSlug packageSlug;
  final double basePrice;
  final int? totalPriceInCents;
  final DateTime expiresAt;
  final Route route;

  RouteFare({
    required this.id,
    required this.packageSlug,
    required this.basePrice,
    this.totalPriceInCents,
    required this.expiresAt,
    required this.route,
  });

  factory RouteFare.fromJson(Map<String, dynamic> json) {
    // Handle both camelCase (mobile) and PascalCase (backend) formats
    final id = json['id']?.toString() ?? json['ID']?.toString() ?? '';
    final packageSlugStr = json['packageSlug']?.toString() ?? json['PackageSlug']?.toString() ?? 'sedan';
    
    // Backend sends totalPriceInCents as float64, convert to int
    int? totalPriceInCents;
    final totalPriceKey = json['totalPriceInCents'] != null ? 'totalPriceInCents' : 
                          json['TotalPriceInCents'] != null ? 'TotalPriceInCents' : null;
    if (totalPriceKey != null) {
      if (json[totalPriceKey] is int) {
        totalPriceInCents = json[totalPriceKey] as int;
      } else if (json[totalPriceKey] is num) {
        totalPriceInCents = (json[totalPriceKey] as num).toInt();
      }
    }
    
    // Use totalPriceInCents as basePrice if basePrice is not provided
    double basePrice = 0.0;
    if (json['basePrice'] != null) {
      basePrice = (json['basePrice'] as num).toDouble();
    } else if (totalPriceInCents != null) {
      basePrice = totalPriceInCents / 100.0;
    }
    
    // Handle route - backend sends Route with routes array
    Route route = Route(geometry: [], duration: 0, distance: 0.0);
    if (json['route'] != null) {
      route = Route.fromJson(json['route'] as Map<String, dynamic>);
    } else if (json['Route'] != null) {
      final routeData = json['Route'] as Map<String, dynamic>;
      // Backend sends Route with routes array, extract first route
      if (routeData['routes'] != null && (routeData['routes'] as List).isNotEmpty) {
        final firstRoute = (routeData['routes'] as List)[0] as Map<String, dynamic>;
        route = Route.fromJson(firstRoute);
      } else {
        route = Route.fromJson(routeData);
      }
    }
    
    return RouteFare(
      id: id,
      packageSlug: CarPackageSlug.fromString(packageSlugStr),
      basePrice: basePrice,
      totalPriceInCents: totalPriceInCents,
      expiresAt: json['expiresAt'] != null 
          ? DateTime.parse(json['expiresAt'].toString())
          : DateTime.now().add(const Duration(hours: 1)),
      route: route,
    );
  }
}

class Driver {
  final String id;
  final Coordinate location;
  final String geohash;
  final String name;
  final String profilePicture;
  final String carPlate;

  Driver({
    required this.id,
    required this.location,
    required this.geohash,
    required this.name,
    required this.profilePicture,
    required this.carPlate,
  });

  factory Driver.fromJson(Map<String, dynamic> json) => Driver(
        id: json['id']?.toString() ?? '',
        location: json['location'] != null
            ? Coordinate.fromJson(json['location'] as Map<String, dynamic>)
            : Coordinate(latitude: 0.0, longitude: 0.0),
        geohash: json['geohash']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        profilePicture: json['profilePicture']?.toString() ?? '',
        carPlate: json['carPlate']?.toString() ?? '',
      );
}

class Trip {
  final String id;
  final String userID;
  final String status;
  final RouteFare selectedFare;
  final Route route;
  final Driver? driver;

  Trip({
    required this.id,
    required this.userID,
    required this.status,
    required this.selectedFare,
    required this.route,
    this.driver,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    // Handle both camelCase (mobile) and PascalCase (backend) formats
    final id = json['id'] ?? json['ID'] ?? '';
    final userID = json['userID'] ?? json['UserID'] ?? '';
    final status = json['status'] ?? json['Status'] ?? '';
    
    // Handle selectedFare/RideFare
    Map<String, dynamic>? fareData;
    if (json['selectedFare'] != null) {
      fareData = json['selectedFare'] as Map<String, dynamic>;
    } else if (json['RideFare'] != null) {
      fareData = json['RideFare'] as Map<String, dynamic>;
    }
    
    // Handle route
    Map<String, dynamic>? routeData;
    if (json['route'] != null) {
      routeData = json['route'] as Map<String, dynamic>;
    } else if (json['Route'] != null) {
      routeData = json['Route'] as Map<String, dynamic>;
    }
    
    // Handle driver
    Map<String, dynamic>? driverData;
    if (json['driver'] != null) {
      driverData = json['driver'] as Map<String, dynamic>;
    } else if (json['Driver'] != null) {
      driverData = json['Driver'] as Map<String, dynamic>;
    }
    
    return Trip(
      id: id,
      userID: userID,
      status: status,
      selectedFare: fareData != null 
          ? RouteFare.fromJson(fareData)
          : RouteFare(
              id: '',
              packageSlug: CarPackageSlug.sedan,
              basePrice: 0.0,
              expiresAt: DateTime.now(),
              route: Route(geometry: [], duration: 0, distance: 0.0),
            ),
      route: routeData != null
          ? Route.fromJson(routeData)
          : Route(geometry: [], duration: 0, distance: 0.0),
      driver: driverData != null
          ? Driver.fromJson(driverData)
          : null,
    );
  }
}

class TripPreview {
  final String tripID;
  final List<Coordinate> route;
  final List<RouteFare> rideFares;
  final int duration;
  final double distance;

  TripPreview({
    required this.tripID,
    required this.route,
    required this.rideFares,
    required this.duration,
    required this.distance,
  });
}

