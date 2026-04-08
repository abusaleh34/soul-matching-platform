import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb

class LocationService {
  /// Fetches the user's city name directly safely traversing permission and web hurdles dynamically.
  /// Returns null seamlessly if natively blocked or denied, supporting manual failover.
  static Future<String?> getCityNatively() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are fundamentally online
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services heavily disabled natively.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location requests successfully denied gracefully.');
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions structurally denied forever.');
      return null;
    }

    try {
      // 10 second timeout block prevents Web instances stalling asynchronously 
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Better yield on Web browsers
        timeLimit: const Duration(seconds: 10),
      );
      
      try {
        // Only run native plugins inherently if outside the strict web-isolation engine
        if (!kIsWeb) {
          List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
          if (placemarks.isNotEmpty) {
             final place = placemarks.first;
             // Extract locality (City metric mapped geographically)
             final city = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? '';
             
             if (city.isNotEmpty && city != 'Unknown') {
               return city;
             }
          }
        }
      } catch (geocodeError) {
         debugPrint("Reverse geocoder blocking web mapping natively: $geocodeError");
      }
      
      // Fallback Strategy: BigDataCloud Reverse Geo-Locating safely
      if (kIsWeb) {
         try {
           final url = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${position.latitude}&longitude=${position.longitude}&localityLanguage=ar');
           final response = await http.get(url).timeout(const Duration(seconds: 10));
           
           if (response.statusCode == 200) {
              final data = json.decode(response.body);
              final city = data['city'] ?? data['locality'] ?? '';
              if (city.isNotEmpty) {
                 return city;
              }
           }
         } catch (httpError) {
           debugPrint("Web HTTP Geolocation fallback failed: $httpError");
         }
      }
      
      return null; 
    } catch (e) {
       debugPrint("Location position isolation error: $e");
       return null;
    }
  }
}
