// // temp.dart
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:background_fetch/background_fetch.dart';

// Timer? _timer;

// /// This function will be called from main.dart when the button is pressed
// Future<void> startLocationService() async {
//   await Firebase.initializeApp();

//   await _initPermissions();
//   _initBackgroundFetch();
//   _startLocationTimer();

//   print("📍 Location service started");
// }

// Future<void> _initPermissions() async {
//   LocationPermission permission = await Geolocator.checkPermission();
//   if (permission == LocationPermission.denied ||
//       permission == LocationPermission.deniedForever) {
//     await Geolocator.requestPermission();
//   }
// }

// void _startLocationTimer() {
//   _timer =
//       Timer.periodic(Duration(seconds: 5), (_) => _fetchAndStoreLocation());
// }

// Future<void> _fetchAndStoreLocation() async {
//   try {
//     Position position = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.high,
//     );

//     await FirebaseFirestore.instance.collection('locations').add({
//       'latitude': position.latitude,
//       'longitude': position.longitude,
//       'timestamp': Timestamp.now(),
//     });
//   } catch (e) {
//     print("❌ Error getting location: $e");
//   }
// }

// void _initBackgroundFetch() {
//   BackgroundFetch.configure(
//     BackgroundFetchConfig(
//       minimumFetchInterval: 15,
//       stopOnTerminate: false,
//       enableHeadless: true,
//       startOnBoot: true,
//       requiresBatteryNotLow: false,
//       requiresCharging: false,
//       requiresStorageNotLow: false,
//       requiredNetworkType: NetworkType.NONE,
//     ),
//     (String taskId) async {
//       await _fetchAndStoreLocation();
//       BackgroundFetch.finish(taskId);
//     },
//   );

//   // Register headless task
//   BackgroundFetch.registerHeadlessTask(_backgroundFetchHeadlessTask);
// }

// // 🔁 Headless background task
// void _backgroundFetchHeadlessTask(String taskId) async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp();

//   Position position = await Geolocator.getCurrentPosition(
//     desiredAccuracy: LocationAccuracy.high,
//   );

//   await FirebaseFirestore.instance.collection('locations').add({
//     'latitude': position.latitude,
//     'longitude': position.longitude,
//     'timestamp': Timestamp.now(),
//   });

//   BackgroundFetch.finish(taskId);
// }
