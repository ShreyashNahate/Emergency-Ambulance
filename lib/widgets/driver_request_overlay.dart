import 'dart:async';
import 'package:flutter/material.dart';

class DriverRequestOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const DriverRequestOverlay({super.key, required this.onComplete});

  @override
  State<DriverRequestOverlay> createState() => _DriverRequestOverlayState();
}

class _DriverRequestOverlayState extends State<DriverRequestOverlay> {
  double progress = 0.0;
  late Timer _timer;
  String status = "Searching for available drivers nearby...";

  @override
  void initState() {
    super.initState();
    _startProgressSimulation();
  }

  void _startProgressSimulation() {
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      setState(() {
        progress += (5 + (5 * (0.5 - (progress / 100))));
        if (progress > 100) progress = 100;

        if (progress < 30) {
          status = "Searching for available drivers nearby...";
        } else if (progress < 70) {
          status = "Contacting selected driver...";
        } else {
          status = "Finalizing request details...";
        }

        if (progress >= 100) {
          _timer.cancel();
          Future.delayed(const Duration(milliseconds: 600), () {
            widget.onComplete();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white.withOpacity(0.95),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.only(bottom: 30),
              width: 80 + (progress % 20),
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: const Icon(Icons.local_hospital,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: LinearProgressIndicator(
                value: progress / 100,
                color: const Color(0xFF4361EE),
                backgroundColor: Colors.grey.shade300,
                minHeight: 6,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "${progress.toInt()}%",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF3A0CA3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
