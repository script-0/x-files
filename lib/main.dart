import 'dart:convert';
import 'dart:developer';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'utils.dart';
import 'package:storage_details/storage_details.dart';

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

  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  late Map<String, dynamic> _deviceInfo;
  List<Storage> _storages = [];

  bool _sharingStarted = false;
  String _accessLink = "";
  late HttpServer _server;
  final int _port = 4000;

  Future<bool> isConnectedToWiFi() async {
    return await WiFiForIoTPlugin.isConnected();
  }

  Future<String?> getWiFiIp() async {
    return await WiFiForIoTPlugin.getIP();
  }

  void startSharing(){
    isConnectedToWiFi().then((value) => share(value));
  }

  void share(bool isConnected){
    if(isConnected){
      getWiFiIp().then((ipAddress) => startServer(ipAddress!));
    }else{
      showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('X File'),
          content: const Text('Not connected to any WiFi Access Point.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, 'OK'),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  startServer(String ipAddress) async {
    HttpServer server = await HttpServer.bind(ipAddress, _port, shared: true);
    log("Server running on IP : " + server.address.toString() + " On Port : " + server.port.toString());
    setState(() {
      _sharingStarted = true;
      _server = server;
      _accessLink = "http://" + ipAddress + ":" + _port.toString();
    });
    await for (final request in server) {
      List<String> requestPathParts = request.requestedUri.toString().split("/");

      // If we are requesting /favicon.ico
      if(requestPathParts.length== 4 && requestPathParts.last=="favicon.ico"){
        final favicon = await rootBundle.load('assets/favicon.ico');
        request.response
            ..headers.contentType = ContentType('image', 'x-icon', charset: 'utf-8')
            ..add(favicon.buffer.asUint8List())
            ..close();
        continue;
      }

      // If we are requesting /info
      if(requestPathParts.length== 4 && requestPathParts.last=="info"){
        request.response
          ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
          ..write(
            jsonEncode({
              'lang' : Platform.localeName,
              'brand' : _deviceInfo["brand"],
              'isPhysicalDevice' : _deviceInfo["isPhysicalDevice"],
              'model' : _deviceInfo["model"],
              'sdk' : _deviceInfo["version.sdkInt"],
              "os" : Platform.operatingSystem,
              "internalStorage" : {
                "root" : _storages.isEmpty ? "" : _storages[0].path,
                "space" : {
                  "free" :  _storages.isEmpty ? "" : _storages[0].free,
                  "total" :  _storages.isEmpty ? "" : _storages[0].total
                }
              },
              "sdCard" : {
                "root" : _storages.length > 1 ? _storages[1].path : "",
                "space" : {
                  "freed" : _storages.length > 1 ? _storages[1].free : "",
                  "total" :_storages.length > 1 ? _storages[1].total : ""
                }
              }
            })
          )
          ..close();
        continue;
      }

      // If we are requesting /internal
      if(requestPathParts.length== 4 && requestPathParts.last=="internal"){
        await _listDir(request, _storages[0].path);
        continue;
      }

      // If we are requesting a file /get?f=<file_path> or a dir list /get?d=<dir_path>
      if(requestPathParts.length > 4 ){
        List<String> requestParams = requestPathParts[3].split("?");
        if(requestParams.length > 1 && requestParams[0]=="get"){
          final requestedFilePath = request.requestedUri.queryParameters['f'] ?? '';

          //requesting a file /get?f=<file_path>
          if(requestedFilePath != '') {
            log("requestedFilePath : " + requestedFilePath);
            bool isDir = await FileSystemEntity.type(requestedFilePath) == FileSystemEntityType.directory;
            if (isDir) {
              request.response
                ..headers.contentType = ContentType(
                    'application', 'json', charset: 'utf-8')
                ..write(
                    jsonEncode({
                      "error": "It's a Directory"
                    })
                )
                ..close();
            } else {
              File file = File(requestedFilePath);
              int size = await file.length();
              await _pipeFile(
                request,
                file,
                size,
                requestedFilePath
                    .split(Platform.pathSeparator)
                    .last,
              );
            }
            continue;
          }
          else{
            final requestedDirPath = request.requestedUri.queryParameters['d'] ?? '';

            //requesting a dir list /get?d=<dir_path>
            if(requestedDirPath != ''){
              Directory folder = Directory(requestedDirPath);
              bool isDir =  folder.existsSync();
              if(isDir){
                _listDir(request, requestedDirPath);
              }else{
                request.response
                  ..headers.contentType = ContentType(
                      'application', 'json', charset: 'utf-8')
                  ..write(
                      jsonEncode({
                        "error": "It's a File or doesn't exists."
                      })
                  )
                  ..close();
              }
              continue;
            }
          }
        }
      }

      request.response
        ..headers.contentType = ContentType("text", "plain", charset: "utf-8")
        ..write('Hello, world')
        ..close();
    }
  }

  void stopSharing(){
    _server.close().then((value) => setState(() {
      _sharingStarted = false;
    })
    );
  }

  void initInfoAndRemoveSplashScreen(){
    // Load Device information
    readDeviceBuildData(_deviceInfoPlugin).then((value) => _deviceInfo=value);

    // Load Storage Info
    StorageDetails.getspace.then((value) => _storages=value).catchError(
      (err) {
        log('Error: $err'); // Prints 401.
      }, test: (error) {
        return error is int && error >= 400;
      });

    FlutterNativeSplash.remove();
  }

  Future<void> _pipeFile(HttpRequest request, File? file, int? size, String fileName) async {
    request.response.headers.contentType =
        ContentType('application', 'octet-stream', charset: 'utf-8');

    request.response.headers.add(
      'Content-Transfer-Encoding',
      'Binary',
    );

    request.response.headers.add(
      'Content-disposition',
      'attachment; filename="${Uri.encodeComponent(fileName)}"',
    );

    if (size != null) {
      request.response.headers.add(
        'Content-length',
        size,
      );
    }

    await file!.openRead().pipe(request.response).catchError((e) {}).then((a) {
      request.response.close();
    });
  }

  Future<void> _listDir( HttpRequest request, String dirPath) async{
    Directory folder = Directory(dirPath);
    request.response
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(
          jsonEncode({
            "files" : ( await folder.list().toList() ).map((e) => e.path.toString()).toList()
          })
      )
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    Color color = const Color.fromRGBO(255, 255, 255, 1);

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
    Widget footer = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildButtonColumn(color, Icons.settings, 'Settings', ()=>{getWiFiIp().then((value) => log("IP : "+ value!))}),
        _buildButtonColumn(color, Icons.star_rate, 'Rate', ()=>{}),
        _buildButtonColumn(color, Icons.share, 'Share', ()=>{}),
      ],
    );

    Future<bool> checkPermission() async {
      bool storagePermission = await Permission.storage.request().isGranted;
      bool locationPermission = await Permission.location.request().isGranted;
      return storagePermission && locationPermission;
    }
    checkPermission().then((value) => initInfoAndRemoveSplashScreen());

    return Scaffold(
      backgroundColor: Colors.blue,
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding : const EdgeInsets.only(top: 40),
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
