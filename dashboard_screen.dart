import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart'; // For the map view
import 'package:latlong2/latlong.dart'; // For LatLng with flutter_map
import 'package:firebase_auth/firebase_auth.dart'; // For admin logout

// Main Dashboard Screen with Bottom Navigation
class dashboard_screen extends StatefulWidget {
  const dashboard_screen({super.key});

  @override
  State<dashboard_screen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<dashboard_screen> {
  int _selectedIndex = 0; // To control which tab is selected
  final FirebaseAuth _auth = FirebaseAuth.instance; // For admin logout

  // List of widgets for each tab in the BottomNavigationBar
  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    // Initialize the list of content widgets for each tab
    _widgetOptions = <Widget>[
      _RequestsAssignmentView(), // Tab 1: Manage Requests & Assign Drivers
      _AvailableAmbulancesMapView(), // Tab 2: Live Map of Ambulances
    ];
  }

  // Callback for when a tab is tapped
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index; // Update the selected index to switch tabs
    });
  }

  // Admin logout functionality
  Future<void> _logout() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      // Display the content widget corresponding to the selected tab
      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
      // Bottom navigation bar to switch between tabs
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment), // Icon for Requests tab
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map), // Icon for Map tab
            label: 'Map',
          ),
        ],
        currentIndex: _selectedIndex, // Currently selected tab
        selectedItemColor: Colors.red, // Color for the selected tab icon/label
        onTap: _onItemTapped, // Callback when a tab is tapped
      ),
    );
  }
}

// --- Tab 1: Widget for displaying Pending Requests and Driver Assignment ---
class _RequestsAssignmentView extends StatefulWidget {
  @override
  __RequestsAssignmentViewState createState() =>
      __RequestsAssignmentViewState();
}

class __RequestsAssignmentViewState extends State<_RequestsAssignmentView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Map to hold selected driver for each request (requestId -> driverId)
  final Map<String, String?> _selectedDriverMap = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "Pending Ambulance Requests",
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Expanded(
          // StreamBuilder to listen for real-time updates to pending requests
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('requests')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, requestSnapshot) {
              if (requestSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (requestSnapshot.hasError) {
                return Center(child: Text("Error: ${requestSnapshot.error}"));
              }
              if (!requestSnapshot.hasData ||
                  requestSnapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No pending requests."));
              }

              final pendingRequests = requestSnapshot.data!.docs;

              return ListView.builder(
                itemCount: pendingRequests.length,
                itemBuilder: (context, index) {
                  final requestDoc = pendingRequests[index];
                  final requestData = requestDoc.data() as Map<String, dynamic>;
                  final userId = requestData['userId'] ?? 'Unknown User';
                  final pickupLocData = requestData['pickupLocation'];
                  final pickupLat = pickupLocData?['lat'] ?? 0.0;
                  final pickupLng = pickupLocData?['lng'] ?? 0.0;
                  final timestamp =
                      (requestData['timestamp'] as Timestamp?)?.toDate();

                  // Use another StreamBuilder for available drivers within each request item
                  // This ensures the dropdown items are always up-to-date
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Request ID: ${requestDoc.id}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text("User ID: $userId"),
                          Text("Pickup Location: ($pickupLat, $pickupLng)"),
                          Text(
                            "Time: ${timestamp != null ? _formatTimestamp(timestamp) : 'N/A'}",
                          ),
                          const SizedBox(height: 10),

                          // StreamBuilder to get available drivers dynamically
                          StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('drivers')
                                .where('isAvailable', isEqualTo: true)
                                .snapshots(),
                            builder: (context, driverSnapshot) {
                              if (driverSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Text(
                                  "Loading available drivers...",
                                );
                              }
                              if (driverSnapshot.hasError) {
                                return const Text("Error loading drivers.");
                              }
                              if (!driverSnapshot.hasData ||
                                  driverSnapshot.data!.docs.isEmpty) {
                                return const Text("No available drivers.");
                              }

                              List<DropdownMenuItem<String>> driverItems = [];
                              driverItems.add(
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Select Driver'), // Hint text
                                ),
                              );

                              for (var doc in driverSnapshot.data!.docs) {
                                final driverData =
                                    doc.data() as Map<String, dynamic>;
                                final driverName = driverData['name'] ?? doc.id;
                                driverItems.add(
                                  DropdownMenuItem(
                                    value: doc.id,
                                    child: Text(
                                      '$driverName (${doc.id.substring(0, 5)}...)',
                                    ),
                                  ),
                                );
                              }

                              // Keep track of the selected driver for this specific request
                              // If a request is new or no driver is selected, default to null
                              String? currentSelection =
                                  _selectedDriverMap[requestDoc.id];
                              if (!driverItems.any(
                                (item) => item.value == currentSelection,
                              )) {
                                currentSelection =
                                    null; // Reset if the selected driver is no longer available
                              }

                              return DropdownButtonFormField<String?>(
                                value: currentSelection,
                                hint: const Text('Assign Driver'),
                                items: driverItems,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedDriverMap[requestDoc.id] =
                                        value; // Update map for this request
                                  });
                                },
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _selectedDriverMap[requestDoc.id] == null
                                ? null // Disable button if no driver is selected for THIS request
                                : () => _assignDriver(
                                      requestDoc.id,
                                      _selectedDriverMap[requestDoc
                                          .id]!, // Use the specific selected driver
                                      userId,
                                    ),
                            child: const Text("Assign Driver"),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Helper to format timestamp
  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.hour}:${timestamp.minute} ${timestamp.day}/${timestamp.month}";
  }

  // Logic to assign a driver to a request
  Future<void> _assignDriver(
    String requestId,
    String driverId,
    String userId,
  ) async {
    try {
      // 1. Update the request status to 'assigned' and link driver
      await _firestore.collection('requests').doc(requestId).update({
        'status': 'assigned',
        'ambulanceId': driverId,
      });

      // 2. Update the driver status to 'busy' and link to the request
      await _firestore.collection('drivers').doc(driverId).update({
        'isAvailable':
            false, // Change from isAvailable: false to status: 'busy'
        'assignedRequestId':
            requestId, // Optional: Link the request ID to the driver
      });

      // 3. Update the user's assignedAmbulanceId in the users collection
      // This is crucial for the user's tracking map to pick up the correct ambulance
      await _firestore.collection('users').doc(userId).update({
        'assignedAmbulanceId': driverId,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Driver assigned successfully!")),
      );
      // After successful assignment, remove the selection from the map to clear the dropdown
      setState(() {
        _selectedDriverMap.remove(requestId);
      });
    } catch (e) {
      print("Error assigning driver: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to assign driver: ${e.toString()}")),
      );
    }
  }
}

// --- Tab 2: Widget for displaying the Live Ambulance Map ---
class _AvailableAmbulancesMapView extends StatefulWidget {
  @override
  __AvailableAmbulancesMapViewState createState() =>
      __AvailableAmbulancesMapViewState();
}

class __AvailableAmbulancesMapViewState
    extends State<_AvailableAmbulancesMapView> {
  final MapController _mapController = MapController();
  late final Widget
      _ambulanceIconWidget; // Widget for the custom ambulance icon

  @override
  void initState() {
    super.initState();
    // Initialize the custom icon from assets
    _ambulanceIconWidget = Image.asset(
      'assets/images/ambulance.png', // Make sure this path is correct in pubspec.yaml
      width: 40, // Adjust size as needed
      height: 40, // Adjust size as needed
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Stream to listen for real-time updates of all drivers
      // You might want to filter this by 'status': 'available' or 'on_duty'
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text("Error loading map data: ${snapshot.error}"),
          );
        }

        final markers = <Marker>[];
        // Populate markers for each driver
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;

          final lat = data['lat'];
          final lng = data['lng'];
          final driverName = data['name'] ?? 'Driver ${doc.id.substring(0, 5)}';
          final driverStatus = data['isAvailable'] ?? false;

          markers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 30, // Slightly larger for better visibility
              height: 30,
              // Using the custom ambulance icon
              child: Tooltip(
                // Add a tooltip for driver info on hover/long press
                message: '$driverName\nStatus: $driverStatus',
                child: _ambulanceIconWidget,
              ),
            ),
          );
        }

        // Determine initial map center if no markers are present, or average of markers
        LatLng initialCenter = LatLng(19.0760, 72.8777); // Default to Mumbai
        if (markers.isNotEmpty) {
          double avgLat =
              markers.map((m) => m.point.latitude).reduce((a, b) => a + b) /
                  markers.length;
          double avgLng =
              markers.map((m) => m.point.longitude).reduce((a, b) => a + b) /
                  markers.length;
          initialCenter = LatLng(avgLat, avgLng);
        }

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 12.0, // Default zoom level
          ),
          children: [
            // OpenStreetMap tile layer
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
            ),
            // Marker layer for ambulance icons
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }
}
