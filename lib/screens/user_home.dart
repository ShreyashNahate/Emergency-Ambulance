import 'package:ambulence/widgets/driver_request_overlay.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'user_tracking_map.dart';

class UserHome extends StatefulWidget {
  const UserHome({super.key});

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  bool isRequesting = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      nameController.text = userDoc['name'] ?? '';
      phoneController.text = userDoc['phone'] ?? '';
    }
  }

  Future<void> _submitUserInfoAndRequestAmbulance() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter name and phone number")),
      );
      return;
    }

    setState(() => isRequesting = true);

    // Step 1: Show Overlay FIRST
    final overlay = Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DriverRequestOverlay(
          onComplete: () {},
        ), // Temporarily no onComplete
      ),
    );

    try {
      // Step 2: Get location
      await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition();

      // Step 3: Firebase writes
      await _firestore.collection("users").doc(user.uid).set({
        'name': name,
        'phone': phone,
        'email': user.email,
        'assignedAmbulanceId': null,
      }, SetOptions(merge: true));

      await _firestore.collection("requests").doc(user.uid).set({
        'userId': user.uid,
        'ambulanceId': null,
        'status': 'pending',
        'pickupLocation': {'lat': pos.latitude, 'lng': pos.longitude},
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Step 4: Pop the overlay ONLY after success
      Navigator.pop(context); // close overlay
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚑 Driver request completed successfully!"),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // close overlay even on error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: ${e.toString()}")),
      );
    }

    setState(() => isRequesting = false);
  }

  Future<void> _cancelRequest() async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('requests').doc(_currentUserId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❎ Request cancelled.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to cancel: ${e.toString()}")),
      );
    }
  }

  Future<void> _openTrackingIfAssigned() async {
    final doc =
        await _firestore.collection('requests').doc(_currentUserId).get();
    final data = doc.data();

    if (data != null &&
        data['status'] == 'assigned' &&
        data['ambulanceId'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserTrackingMap()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚨 Ambulance not assigned yet.")),
      );
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return const Scaffold(body: Center(child: Text("Please log in.")));
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("🚑 Ambulance App"),
            backgroundColor: Colors.red.shade600,
            actions: [
              IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text("🧍 Your Details",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: "👤 Name"),
                    ),
                    TextField(
                      controller: phoneController,
                      decoration:
                          const InputDecoration(labelText: "📞 Phone Number"),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.local_hospital),
                      label: const Text("Request Ambulance"),
                      onPressed: isRequesting
                          ? null
                          : _submitUserInfoAndRequestAmbulance,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text("Track Ambulance"),
                      onPressed: _openTrackingIfAssigned,
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<DocumentSnapshot>(
                      stream: _firestore
                          .collection('requests')
                          .doc(_currentUserId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        try {
                          final requestStatus = snapshot.data?.get('status');
                          if (requestStatus == 'pending' ||
                              requestStatus == 'assigned') {
                            return ElevatedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: const Text("Cancel Request"),
                              onPressed: _cancelRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade800,
                              ),
                            );
                          }
                        } catch (e) {
                          // Document might not exist or have no 'status' field – ignore
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
