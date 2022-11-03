import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io'; // Add this import.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message ${message.messageId}');
}

bool _foundDeviceWaitingToConnect = false;
bool _scanStarted = false;
bool _connected = false;
// Bluetooth related variables
// late DiscoveredDevice _ubiqueDevice;
// late StreamSubscription<DiscoveredDevice> _scanStream;
// late QualifiedCharacteristic _rxCharacteristic;
// final serviceUUID = Uuid.parse("5fafc201-1fb5-459e-8fcc-c5c9c331914b");
// final charUUID = Uuid.parse("eeb5483e-36e1-4688-b7f5-ea07361b26a8");
// final flutterReactiveBle = FlutterReactiveBle();

late AndroidNotificationChannel channel;
late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
var token;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  channel = const AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.high,
  );

  var initialzationSettingsAndroid =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  var initialzationSettingsIOS = const DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  var initializationSettings = InitializationSettings(
      android: initialzationSettingsAndroid, iOS: initialzationSettingsIOS);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  // flutterReactiveBle.statusStream.listen((status) {
  //   //code for handling status update
  //   print(status);
  // });
  token = await FirebaseMessaging.instance.getToken();
  print("token : ${token ?? 'token NULL!'}");

  runApp(
    const MaterialApp(
      home: WebViewApp(),
    ),
  );
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({Key? key}) : super(key: key);

  @override
  State<WebViewApp> createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  WebViewController? _controller;
  BeaconBroadcast beaconBroadcast = BeaconBroadcast();

  @override
  void initState() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      var androidNotiDetails = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
      );
      var iOSNotiDetails = const DarwinNotificationDetails();
      var details =
          NotificationDetails(android: androidNotiDetails, iOS: iOSNotiDetails);
      if (notification != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          details,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print(message);
    });
    if (Platform.isAndroid) {
      WebView.platform = SurfaceAndroidWebView();
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _goBack(context),
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size(double.infinity, 0),
          child: Visibility(
            visible: true,
            child: AppBar(),
          ),
        ),
        body: WebView(
          userAgent:
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/106.0.0.0 Safari/537.36',
          initialUrl: 'https://lockscale.kro.kr/',
          javascriptMode: JavascriptMode.unrestricted,
          onWebViewCreated: (WebViewController webviewController) {
            _controller = webviewController;
          },
          onProgress: (int progress) {
            log("WebView is loading (progress : $progress%)", name: 'test.ctr');
          },
          onPageStarted: (String url) {
            log('Page started loading: $url', name: 'test.ctr');
          },
          onPageFinished: (String url) {
            log('Page finished loading: $url', name: 'test.ctr');
          },
          javascriptChannels: {
            JavascriptChannel(
                name: 'JavaScriptChannel',
                onMessageReceived: (JavascriptMessage message) {
                  print(message.message);
                  var val = jsonDecode(message.message);
                  if (val['type'] == "msg") {
                    showDialog<String>(
                        context: context,
                        builder: (BuildContext context) =>
                            alertShow("알림", val['value']));
                  } else if (val['type'] == "uuid") {
                    beaconBroadcast.stop();
                    beaconBroadcast = BeaconBroadcast();
                    if (val['value'] == "") {
                      return;
                    }
                    beaconBroadcast
                        .setUUID(val['value'])
                        .setMajorId(10)
                        .setMinorId(150)
                        .setIdentifier(
                            'com.example.myDeviceRegion') //iOS-only, optional
                        .setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24')
                        .setManufacturerId(0x004C)
                        .start();

                    print("beacon start complete");
                  } else if (val['type'] == "state" &&
                      val['value'] == "login_complete") {
                    _controller?.runJavascript("is_app();");
                    _controller?.runJavascript("send_to_web('${token}');");
                  }
                })
          },
        ),
      ),
    );
  }

  Future<bool> _goBack(BuildContext context) async {
    bool? c = await _controller?.canGoBack();
    if (c != null && c) {
      _controller?.goBack();
      return Future.value(false);
    } else {
      return Future.value(true);
    }
  }

  AlertDialog alertShow(title, content) {
    return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('완료'),
          ),
        ]);
  }
}
