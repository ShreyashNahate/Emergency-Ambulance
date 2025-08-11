import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final driverId = FirebaseAuth.instance.currentUser?.uid;
  Timer? _locationTimer;
  String? activeRequestId;
  String? patientPhone;
  bool tripAssigned = false;

  @override
  void initState() {
    super.initState();
    _setupMessaging();
    _startLiveLocationUpdates();
  }

  Future<void> _setupMessaging() async {
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && driverId != null) {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .set({'fcmToken': token}, SetOptions(merge: true));
      print("✅ Driver FCM token saved: $token");
    }

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("🔔 ${notification.title}: ${notification.body}")),
        );
      }
    });
  }

  Future<void> _startLiveLocationUpdates() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = await Geolocator.getCurrentPosition();
      if (driverId == null) return;
      await FirebaseFirestore.instance.collection('drivers').doc(driverId).set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'isAvailable': !tripAssigned,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _acceptRequest(String requestId) async {
    if (driverId == null) return;

    final requestDoc = await FirebaseFirestore.instance
        .collection('requests')
        .doc(requestId)
        .get();
    final requestData = requestDoc.data();
    if (requestData == null) return;

    final pickup = requestData['pickupLocation'];
    final userId = requestData['userId'];
    if (pickup == null || pickup['lat'] == null || pickup['lng'] == null) {
      return;
    }

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    final userData = userDoc.data();
    if (userData != null) patientPhone = userData['phone'];

    await FirebaseFirestore.instance
        .collection('requests')
        .doc(requestId)
        .update({'ambulanceId': driverId, 'status': 'assigned'});

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .update({'isAvailable': false});

    setState(() {
      activeRequestId = requestId;
      tripAssigned = true;
    });

    final lat = pickup['lat'];
    final lng = pickup['lng'];
    final googleMapsUrl = Uri.parse(
        "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving");
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _endTrip() async {
    if (activeRequestId == null || driverId == null) return;

    await FirebaseFirestore.instance
        .collection('requests')
        .doc(activeRequestId)
        .update({'status': 'completed'});

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .update({'isAvailable': true});

    setState(() {
      activeRequestId = null;
      tripAssigned = false;
      patientPhone = null;
    });
  }

  Future<void> _callPatient() async {
    if (patientPhone == null) return;
    final phoneUri = Uri.parse("tel:$patientPhone");
    if (await canLaunchUrl(phoneUri)) await launchUrl(phoneUri);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
        backgroundColor: Colors.blue.shade800,
        elevation: 5,
      ),
      body: tripAssigned
          ? _buildActiveTripUI()
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('requests')
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("🎉 No pending requests."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final pickup = data['pickupLocation'];

                    return Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text("📦 Request ID: ${doc.id}",
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: pickup != null
                            ? Text("📍 ${pickup['lat']}, ${pickup['lng']}")
                            : const Text("No location data"),
                        trailing: IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () => _acceptRequest(doc.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _resumeNavigationToPatient() async {
    if (activeRequestId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active trip to navigate.')),
      );
      return;
    }

    try {
      final driverPos = await Geolocator.getCurrentPosition();
      final requestDoc = await FirebaseFirestore.instance
          .collection('requests')
          .doc(activeRequestId!)
          .get();

      final data = requestDoc.data();
      if (data == null || data['pickupLocation'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pickup location not available.")),
        );
        return;
      }

      final pickup = data['pickupLocation'];
      final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${driverPos.latitude},${driverPos.longitude}'
        '&destination=${pickup['lat']},${pickup['lng']}'
        '&travelmode=driving',
      );

      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch Google Maps.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Widget _buildActiveTripUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_hospital, size: 80, color: Colors.red),
                const SizedBox(height: 10),
                const Text("🚑 Trip In Progress",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _resumeNavigationToPatient,
                  icon: const Icon(Icons.navigation),
                  label: const Text("Return to Navigation"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _callPatient,
                  icon: const Icon(Icons.phone),
                  label: const Text("Call Patient"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _endTrip,
                  icon: const Icon(Icons.done_all),
                  label: const Text("End Trip"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
