// lib/firebase_options.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBn5lbTDh5ocjje-a1koawSd9sYTQdiMnA',
    authDomain: 'near-u-final.firebaseapp.com',
    projectId: 'near-u-final',
    storageBucket: 'near-u-final.appspot.com',
    messagingSenderId: '519011700291',
    appId:
        '1:519011700291:web:abcdef1234567890', // Replace with your real web appID
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBn5lbTDh5ocjje-a1koawSd9sYTQdiMnA',
    appId: '1:519011700291:android:e61ee69bd8b5ce4e3c8ef6',
    messagingSenderId: '519011700291',
    projectId: 'near-u-final',
    storageBucket: 'near-u-final.appspot.com',
  );
}
