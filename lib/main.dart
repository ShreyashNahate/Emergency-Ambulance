import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/user_home.dart';
import 'screens/driver_home.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseMessaging.instance.requestPermission();

  runApp(const EmerAmbuApp());
}

class EmerAmbuApp extends StatelessWidget {
  const EmerAmbuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EmerAmbu',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          final user = snapshot.data!;
          final email = user.email ?? '';

          if (email.contains("admin")) {
            return const dashboard_screen(); // Redirect to Admin Dashboard
          }
          final isDriver = email.contains("driver"); // you can change logic
          return isDriver ? const DriverHome() : const UserHome();
        }
        return const LoginScreen();
      },
    );
  }
}

// Dummy login page
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();

  Future<void> login() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: pass.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Login failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: login, child: const Text("Login")),
          ],
        ),
      ),
    );
  }
}

// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:workmanager/workmanager.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:geolocator/geolocator.dart';

// const fetchLocationTask = "fetchLocationBackgroundTask";

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp();
//   await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
//   runApp(MyApp());
// }

// void callbackDispatcher() {
//   Workmanager().executeTask((task, inputData) async {
//     await Firebase.initializeApp();
//     Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high);

//     await FirebaseFirestore.instance.collection("locations").add({
//       "latitude": position.latitude,
//       "longitude": position.longitude,
//       "timestamp": Timestamp.now(),
//     });

//     print("📍 Location stored from background");
//     return Future.value(true);
//   });
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   Future<void> startLocationTask() async {
//     LocationPermission permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied ||
//         permission == LocationPermission.deniedForever) {
//       await Geolocator.requestPermission();
//     }

//     await Workmanager().registerPeriodicTask(
//       "uniqueLocationTaskId",
//       fetchLocationTask,
//       frequency: const Duration(minutes: 15), // Minimum interval on Android
//       constraints: Constraints(
//         networkType: NetworkType.connected,
//         requiresBatteryNotLow: false,
//         requiresCharging: false,
//       ),
//     );
//     print("📍 Background location task registered");
//   }

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Location Tracker',
//       home: Scaffold(
//         appBar: AppBar(title: Text("Location Tracker")),
//         body: Center(
//           child: ElevatedButton(
//             onPressed: () async {
//               await startLocationTask();
//             },
//             child: Text("Start Background Location"),
//           ),
//         ),
//       ),
//     );
//   }
// }
