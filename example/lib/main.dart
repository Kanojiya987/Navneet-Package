import 'package:flutter/material.dart';
import 'package:geo_camera_pro/geo_camera_pro.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.geoCamera});

  final GeoCameraPro? geoCamera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo Camera Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: GeoCameraView(
        controller: geoCamera,
        onCapture: (result) {
          debugPrint('Photo captured at: ${result.imagePath}');
        },
      ),
    );
  }
}
