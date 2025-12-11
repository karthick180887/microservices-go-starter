// Simple geohash implementation
class GeohashUtils {
  static const String base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  
  static List<List<double>> getGeohashBounds(String geohash) {
    // Decode geohash to get bounds
    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;
    bool isEven = true;
    
    for (int i = 0; i < geohash.length; i++) {
      final char = geohash[i];
      final index = base32.indexOf(char);
      if (index == -1) continue;
      
      for (int j = 4; j >= 0; j--) {
        final bit = (index >> j) & 1;
        if (isEven) {
          final mid = (minLng + maxLng) / 2;
          if (bit == 1) {
            minLng = mid;
          } else {
            maxLng = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if (bit == 1) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        isEven = !isEven;
      }
    }
    
    return [
      [minLat, minLng],
      [maxLat, maxLng],
    ];
  }
  
  static String encode(double latitude, double longitude, int precision) {
    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;
    final buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;
    
    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }
      
      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    
    return buffer.toString();
  }
}

