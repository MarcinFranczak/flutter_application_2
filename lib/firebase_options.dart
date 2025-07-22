import 'package:flutter/foundation.dart' show kIsWeb; // Usunięto defaultTargetPlatform
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError('DefaultFirebaseOptions have not been configured for this platform');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCVKXCZxdyhqCIGXgyNAcmi5H_ntfYWzao',
    appId: '1:501638073379:android:7d2c70f365d4f3ed07f596',
    messagingSenderId: 'tutaj-wstaw-prawdziwy-messagingSenderId',
    projectId: 'produkty-logowanie',
    authDomain: 'tutaj-wstaw-prawdziwy-authDomain',
    storageBucket: 'tutaj-wstaw-prawdziwy-storageBucket',
    measurementId: 'tutaj-wstaw-prawdziwy-measurementId',
  );
}