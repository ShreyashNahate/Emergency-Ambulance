import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geolocator/geolocator.dart';

class UserTrackingMap extends StatefulWidget {
  const UserTrackingMap({super.key});

  @override
  State<UserTrackingMap> createState() => _UserTrackingMapState();
}

class _UserTrackingMapState extends State<UserTrackingMap> {
  LatLng? driverLocation;
  LatLng? patientLocation;
  String? driverId;
  List<LatLng> routePoints = [];
  Timer? _locationUpdateTimer;
  bool _isRouteLoading = false;
  final double _currentRotation = 0.0;

  Timer? _routeLoadingTimeout;

  final MapController mapController = MapController();

  @override
  void initState() {
    super.initState();
    _listenToRequestAndDriver();
    _getInitialUserLocation();
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _routeLoadingTimeout?.cancel();
    super.dispose();
  }

  Future<void> _getInitialUserLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Location permission denied. Map might not center correctly.")),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (patientLocation == null && driverLocation == null) {
        mapController.move(LatLng(position.latitude, position.longitude),
            mapController.camera.zoom);
      }
    } catch (e) {
      debugPrint("Error getting initial user location: $e");
    }
  }

  void _listenToRequestAndDriver() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showErrorSnackBar("User not logged in.");
      return;
    }

    FirebaseFirestore.instance
        .collection('requests')
        .doc(userId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) {
        setState(() {
          driverLocation = null;
          patientLocation = null;
          driverId = null;
          routePoints = [];
          tripCompletedOrCancelled();
        });
        return;
      }

      final data = doc.data();
      if (data == null) {
        _showErrorSnackBar("Request data is empty.");
        return;
      }

      final String status = data['status'] ?? 'pending';
      if (status == 'completed' || status == 'cancelled') {
        setState(() {
          driverLocation = null;
          patientLocation = null;
          driverId = null;
          routePoints = [];
          tripCompletedOrCancelled();
        });
        return;
      }

      final pickup = data['pickupLocation'];
      if (pickup != null && pickup['lat'] != null && pickup['lng'] != null) {
        setState(() {
          patientLocation = LatLng(pickup['lat'], pickup['lng']);
        });
      } else {
        debugPrint("Patient location missing in request data.");
        _showErrorSnackBar("Patient pickup location is missing.");
      }

      final String? newDriverId = data['ambulanceId'];
      if (newDriverId != null && newDriverId != driverId) {
        setState(() {
          driverId = newDriverId;
        });
        _listenToDriverLocation(driverId!);
      } else if (newDriverId == null && driverId != null) {
        _locationUpdateTimer?.cancel();
        setState(() {
          driverId = null;
          driverLocation = null;
          routePoints = [];
        });
      }
    }, onError: (error) {
      debugPrint("Error listening to request: $error");
      _showErrorSnackBar("Error fetching request details: $error");
    });
  }

  void _listenToDriverLocation(String driverId) {
    _locationUpdateTimer?.cancel();
    _updateDriverLocation(driverId);

    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _updateDriverLocation(driverId);
    });
  }

  void _updateDriverLocation(String driverId) {
    FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .get()
        .then((doc) {
      if (!doc.exists) {
        debugPrint("Driver document $driverId not found.");
        _showErrorSnackBar("Assigned driver not found or has logged out.");
        setState(() {
          driverLocation = null;
        });
        _locationUpdateTimer?.cancel();
        return;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint("Driver data for $driverId is empty.");
        _showErrorSnackBar("Driver data is empty.");
        return;
      }

      if (data['lat'] != null && data['lng'] != null) {
        final newDriverLocation = LatLng(data['lat'], data['lng']);

        setState(() {
          driverLocation = newDriverLocation;
        });

        if (driverLocation != null) {
          mapController.move(driverLocation!, mapController.camera.zoom);
        }

        if (patientLocation != null &&
            driverLocation != null &&
            (routePoints.isEmpty ||
                Distance().as(
                        LengthUnit.Meter, driverLocation!, routePoints.last) >
                    30)) {
          _getRouteBetweenPoints(driverLocation!, patientLocation!);
        }
      } else {
        debugPrint("Driver location (lat/lng) missing for $driverId.");
        _showErrorSnackBar("Driver location data is incomplete.");
      }
    }).catchError((error) {
      debugPrint("Error fetching driver location: $error");
      _showErrorSnackBar("Error tracking driver: $error");
    });
  }

  Future<void> _getRouteBetweenPoints(LatLng start, LatLng end) async {
    if (_isRouteLoading) {
      return;
    }

    setState(() {
      _isRouteLoading = true;
    });

    _routeLoadingTimeout?.cancel();
    _routeLoadingTimeout = Timer(const Duration(seconds: 15), () {
      if (_isRouteLoading) {
        debugPrint("Route loading timed out.");
        setState(() {
          _isRouteLoading = false;
        });
        _showErrorSnackBar("Failed to load route in time. Please try again.");
      }
    });

    try {
      final baseUrl = 'https://router.project-osrm.org';
      final response = await http.get(
        Uri.parse(
          '$baseUrl/route/v1/driving/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}?overview=full&geometries=geojson',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coordinates =
              data['routes'][0]['geometry']['coordinates'] as List;

          setState(() {
            routePoints = coordinates
                .map(
                    (coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
                .toList();
          });

          if (routePoints.isNotEmpty) {
            final allPoints = [...routePoints, start, end];
            final bounds = LatLngBounds.fromPoints(allPoints);
            mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(80.0),
              ),
            );
          }
        } else {
          debugPrint('No routes found between points.');
          _showErrorSnackBar("No route found for this trip.");
          setState(() {
            routePoints = [];
          });
        }
      } else {
        debugPrint(
            'OSRM Route request failed: ${response.statusCode}, Body: ${response.body}');
        _showErrorSnackBar('Failed to get route: ${response.statusCode}');
        setState(() {
          routePoints = [];
        });
      }
    } catch (e) {
      debugPrint('Error getting route: $e');
      _showErrorSnackBar('Error drawing route: $e');
      setState(() {
        routePoints = [];
      });
    } finally {
      setState(() {
        _isRouteLoading = false;
      });
      _routeLoadingTimeout?.cancel();
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void tripCompletedOrCancelled() {
    _locationUpdateTimer?.cancel();
    _routeLoadingTimeout?.cancel();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Trip has been completed or cancelled."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];

    if (patientLocation != null) {
      markers.add(
        Marker(
          point: patientLocation!,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.location_on,
            size: 40,
            color: Colors.blue,
          ),
        ),
      );
    }

    if (driverLocation != null) {
      markers.add(
        Marker(
          point: driverLocation!,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.local_hospital,
            size: 40,
            color: Colors.red,
          ),
        ),
      );
    }

    final LatLng initialCenter =
        driverLocation ?? patientLocation ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Track Ambulance"),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        actions: [
          if (driverLocation != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: () {
                mapController.move(driverLocation!, mapController.camera.zoom);
              },
              tooltip: 'Center on ambulance',
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
              onMapReady: () {
                if (patientLocation != null && driverLocation != null) {
                  _getRouteBetweenPoints(driverLocation!, patientLocation!);
                } else if (patientLocation != null) {
                  mapController.move(
                      patientLocation!, mapController.camera.zoom);
                }
              },
              interactionOptions: const InteractionOptions(
                flags: ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.ambulance_tracker',
              ),
              CurrentLocationLayer(),
              if (routePoints.isNotEmpty)
                PolylineLayer(
                  // Removed explicit type argument
                  polylines: [
                    Polyline(
                      points: routePoints,
                      color: Colors.blue,
                      strokeWidth: 5.0,
                      // Removed isDotted: true as it's not supported in flutter_map 8.1.1
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          if (_isRouteLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (driverLocation != null) {
            mapController.move(driverLocation!, mapController.camera.zoom);
          } else if (patientLocation != null) {
            mapController.move(patientLocation!, mapController.camera.zoom);
          } else {
            _showErrorSnackBar("No valid location to center on.");
          }
        },
        tooltip: 'Center map',
        child: const Icon(Icons.gps_fixed),
      ),
    );
  }
}
