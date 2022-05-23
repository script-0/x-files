import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X Files',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'X Files'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  bool _sharingStarted = false;
  String _accessLink = "http.//192.168.8.100:4000";

  void startSharing(){
    setState(() {
      _sharingStarted = true;
    });
  }

  void stopSharing(){
    setState(() {
      _sharingStarted = false;
    });
  }

  Future<bool> isConnectedToWiFi() async {
    return await WiFiForIoTPlugin.isConnected();
  }

  Future<String?> getWiFiIp() async {
    return await WiFiForIoTPlugin.getIP();
  }

  @override
  Widget build(BuildContext context) {

    Future<bool> checkPermission() async {
      bool storagePermission = await Permission.storage.request().isGranted;
      bool locationPermission = await Permission.location.request().isGranted;
      return storagePermission && locationPermission;
    }

    checkPermission().then((value) => FlutterNativeSplash.remove());

    Column _buildButtonColumn(Color color, IconData icon, String tooltip,  VoidCallback? action) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: action,
            icon: Icon(icon, color: color),
            tooltip: tooltip,
          )
        ],
      );
    }
    Color color = const Color.fromRGBO(255, 255, 255, 1);

    Widget footer = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildButtonColumn(color, Icons.settings, 'Settings', ()=>{getWiFiIp().then((value) => log("IP : "+ value!))}),
        _buildButtonColumn(color, Icons.star_rate, 'Rate', ()=>{}),
        _buildButtonColumn(color, Icons.share, 'Share', ()=>{log("Click on Share")}),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding : const EdgeInsets.only(top: 60),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/x_logo_white.png',
                    width: 100,
                  ),
                  const Text(
                    ' Files',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w700
                    ),
                  )
                ],
              )
            ),
            Expanded(
              child: Column (
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if(_sharingStarted)
                    Container(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _accessLink,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25
                        ),
                      ),
                    )
                  ,
                  if(_sharingStarted)
                    Container(
                      padding : const EdgeInsets.only(bottom: 10),
                      child: const Text(
                        "Open this address in your browser",
                        style: TextStyle(
                          color: Colors.white70,
                            fontSize: 18
                        ),
                      ),
                  ),
                  if(_sharingStarted)
                    Container(
                      padding : const EdgeInsets.only(bottom: 10),
                      child: const Text(
                        "Tap to share this url",
                        style: TextStyle(
                            color: Colors.white70,
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _sharingStarted ? stopSharing : startSharing,
                        child: _sharingStarted ? const Icon(Icons.stop , color: Colors.white, size: 60) : const Icon(Icons.power_settings_new, color: Colors.white, size: 60),
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(40),
                          primary: Colors.blue, // <-- Button color
                          onPrimary: Colors.black, // <-- Splash color
                        ),
                      )
                    ],
                  )
                ],
              )
            ),
            Container(
              padding: const EdgeInsets.only(bottom: 20),
              child: footer,
            )
          ],
        ),
      )
    );
  }


}
