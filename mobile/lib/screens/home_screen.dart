import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package_screen.dart';
import 'rider_map_screen.dart';
import 'driver_map_screen.dart';
import '../models/types.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userType;
  CarPackageSlug? _selectedPackage;

  @override
  Widget build(BuildContext context) {
    if (_userType == null) {
      return _buildWelcomeScreen();
    }

    if (_userType == 'driver' && _selectedPackage == null) {
      return PackageScreen(
        onSelect: (package) {
          setState(() {
            _selectedPackage = package;
          });
        },
      );
    }

    if (_userType == 'driver' && _selectedPackage != null) {
      return DriverMapScreen(
        packageSlug: _selectedPackage!,
        userId: const Uuid().v4(),
      );
    }

    if (_userType == 'rider') {
      return RiderMapScreen(userId: const Uuid().v4());
    }

    return _buildWelcomeScreen();
  }

  Widget _buildWelcomeScreen() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Welcome to RideShare',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose how you\'d like to use our service today',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _userType = 'rider';
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                        ),
                        child: const Text(
                          'I Need a Ride',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _userType = 'driver';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'I Want to Drive',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

