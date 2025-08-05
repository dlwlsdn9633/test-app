import 'dart:isolate';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

//import 'package:firebase_core/firebase_core.dart';
//import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'constants.dart';

/*
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔕 백그라운드 메시지 수신: ${message.messageId}");
}
*/

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //await Firebase.initializeApp();
  //FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FlutterDownloader.initialize(debug: true, ignoreSsl: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '대아이엔지',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final WebViewController _controller;
  final ReceivePort _port = ReceivePort();
  String? _fcmToken;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // ✅ iOS용 설정 추가
    const iOSInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iOSInit, // 👈 이거 꼭 추가해야 해
    );
    flutterLocalNotificationsPlugin.initialize(initSettings);

    /*
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 포그라운드 메시지 수신됨!');
      if (message.notification != null) {
        final title = message.notification!.title ?? '알림';
        final body = message.notification!.body ?? '';

        flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              '알림 채널',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔄 알림을 통해 앱이 열림!');
    });

    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        setState(() {
          _fcmToken = token;
        });
        debugPrint('📲 FCM 디바이스 토큰 앱에 저장됨: $token');
      }
    });
*/
    _requestPermissions();

    // FlutterDownloader 콜백 등록
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );
    _port.listen((dynamic data) {
      String id = data[0];
      int status = data[1];
      int progress = data[2];

      debugPrint('Task $id status: $status, progress: $progress%');
    });

    FlutterDownloader.registerCallback(downloadCallback);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView 로딩 중 (진행률: $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('페이지 로드 시작: $url');
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            debugPrint('페이지 로드 완료: $url');
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
페이지 리소스 오류:
  코드: ${error.errorCode}
  설명: ${error.description}
  유형: ${error.errorType}
  메인 프레임 오류: ${error.isForMainFrame}
            ''');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('페이지 로드 오류 발생: ${error.description}')),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;

            if (url.contains('/download.jsp') ||
                url.endsWith('.pdf') ||
                url.endsWith('.jpg') ||
                url.endsWith('.jpeg') ||
                url.endsWith('.png') ||
                url.endsWith('.gif') ||
                url.endsWith('.doc') ||
                url.endsWith('.docx') ||
                url.endsWith('.xls') ||
                url.endsWith('.xlsx') ||
                url.endsWith('.ppt') ||
                url.endsWith('.pptx') ||
                url.endsWith('.zip') ||
                url.endsWith('.mp3') ||
                url.endsWith('.mp4')) {
              await _startDownload(url);
              return NavigationDecision.prevent;
            }

            if (request.url.startsWith('https://www.youtube.com/')) {
              debugPrint('YouTube 링크로 이동 차단: ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('탐색 허용: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'SingleImageFileChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          debugPrint('웹뷰에서 메시지 수신: ${message.message}');
          if (message.message == 'requestSingleImageFile') {
            final ImagePicker picker = ImagePicker();
            final XFile? file = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 70,
            );
            if (file != null) {
              final bytes = await File(file.path).readAsBytes();
              final base64String = base64Encode(bytes);
              final mimeType = file.mimeType ?? 'application/octet-stream';
              final fileName = file.name;
              final dataUrl = "data:$mimeType;base64,$base64String";

              debugPrint(dataUrl);

              _controller.runJavaScript(
                'window.handleSingleImageFileSelection(${jsonEncode(dataUrl)}, ${jsonEncode(fileName)})',
              );
            }
          }
        },
      )
      ..addJavaScriptChannel(
        'MultiImageFileChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          debugPrint("웹뷰에서 메시지 수신: ${message.message}");
          if (message.message == 'requestMultiFiles') {
            final ImagePicker picker = ImagePicker();
            final List<XFile>? files = await picker.pickMultiImage(
              imageQuality: 70,
            );

            if (files != null && files.isNotEmpty) {
              List<Map<String, String>> fileDataList = [];
              for (XFile file in files) {
                final bytes = await File(file.path).readAsBytes();
                final base64String = base64Encode(bytes);
                final mimeType = file.mimeType ?? 'application/octet-stream';
                final fileName = file.name;
                final dataUrl = "data:$mimeType;base64,$base64String";

                fileDataList.add({
                  'dataUrl': dataUrl,
                  'fileName': fileName,
                  'mimeType': mimeType,
                });
              }
              _controller.runJavaScript(
                'window.handleMultiFileSelection(${jsonEncode(fileDataList)})',
              );
            } else {
              _controller.runJavaScript('window.handleMultiFileSelection([])');
            }
          }
        },
      )
      ..addJavaScriptChannel(
        'SingleFileChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          if (message.message == 'requestSingleFile') {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.any,
              allowMultiple: false,
              withData: true,
            );

            if (result != null && result.files.single.bytes != null) {
              final platformFile = result.files.single;
              final bytes = platformFile.bytes!;
              final base64String = base64Encode(bytes);

              String? mimeType;
              if (platformFile.path != null) {
                mimeType = lookupMimeType(platformFile.path!);
              }

              if (mimeType == null || mimeType.isEmpty) {
                final ext = platformFile.extension?.toLowerCase() ?? '';
                switch (ext) {
                  case 'jpg':
                  case 'jpeg':
                    mimeType = 'image/jpeg';
                    break;
                  case 'png':
                    mimeType = 'image/png';
                    break;
                  case 'gif':
                    mimeType = 'image/gif';
                    break;
                  case 'pdf':
                    mimeType = 'application/pdf';
                    break;
                  case 'doc':
                  case 'docx':
                    mimeType = 'application/msword';
                    break;
                  case 'xls':
                  case 'xlsx':
                    mimeType = 'application/vnd.ms-excel';
                    break;
                  case 'ppt':
                  case 'pptx':
                    mimeType = 'application/vnd.ms-powerpoint';
                    break;
                  case 'txt':
                    mimeType = 'text/plain';
                    break;
                  case 'mp4':
                    mimeType = 'video/mp4';
                    break;
                  case 'mp3':
                    mimeType = 'audio/mpeg';
                    break;
                  default:
                    mimeType = 'application/octet-stream';
                }
              }

              mimeType ??= 'application/octet-stream';
              final fileName = platformFile.name;
              final dataUrl = "data:$mimeType;base64,$base64String";

              debugPrint(
                "File selected: $fileName (MIME: $mimeType, Size: ${platformFile.size} bytes)",
              );
              debugPrint(
                "Data URL (truncated): ${dataUrl.substring(0, dataUrl.length > 100 ? 100 : dataUrl.length)}...",
              );

              _controller.runJavaScript(
                'window.handleSingleFileSelection(${jsonEncode({'dataUrl': dataUrl, 'fileName': fileName, 'mimeType': mimeType, 'fileSize': platformFile.size})})',
              );
            } else {
              debugPrint("File selection cancelled or failed.");
              _controller.runJavaScript(
                'window.handleSingleFileSelection(null)',
              );
            }
          }
        },
      )
      ..addJavaScriptChannel(
        'SNSLoginChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          debugPrint("SNSLoginChannel 메시지 수신: ${message.message}");
          // JSP에서 'LOGIN_SUCCESS' 메시지를 보냈을 때 처리합니다.
          debugPrint("message: ${message.message}");
          if (message.message.startsWith('LOGIN_SUCCESS')) {
            final no = message.message.split(':')[1];
            if (_fcmToken != null && no.isNotEmpty) {
              await sendFcmTokenToServer(no, _fcmToken!);
            }
            _controller.runJavaScript("window.location.href='/index.jsp'");
          } else {
            debugPrint('알 수 없는 SNSLoginChannel message: ${message.message}');
          }
        },
      )
      ..addJavaScriptChannel(
        'LoginSuccessChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          debugPrint("LoginSuccessChannel 수신: ${message.message}");
          if (message.message.startsWith('LOGIN_SUCCESS')) {
            final no = message.message.split(':')[1];
            if (_fcmToken != null && no.isNotEmpty) {
              await sendFcmTokenToServer(no, _fcmToken!);
            }
          }
          //_controller.runJavaScript("window.location.href='/index.jsp'");
        },
      )
      ..loadRequest(Uri.parse('https://daeaeng.vizensoft.com/'));
  }

  Future<void> sendFcmTokenToServer(String no, String fcmToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/saveToken.jsp'),
        body: {
          'no': no,
          'fcmToken': fcmToken,
          'flutterMessage': 'store_fcmToken',
        },
      );
      if (response.statusCode == 200) {
        debugPrint('✅ FCM 토큰 서버 전송 성공 $fcmToken');
      } else {
        debugPrint('❌ FCM 토큰 서버 전송 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("$e");
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
      Permission.microphone,
      Permission.notification,
    ].request();

    if (statuses[Permission.camera]?.isGranted == true) {
      debugPrint('카메라 권한 허용됨');
    } else if (statuses[Permission.camera]?.isDenied == true) {
      debugPrint('카메라 권한 거부됨');
    }

    if (statuses.values.any(
      (status) => status.isPermanentlyDenied || status.isRestricted,
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('필수 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.'),
            action: SnackBarAction(
              label: '설정 열기',
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _startDownload(String url) async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    }

    if (dir == null) {
      debugPrint("저장할 디렉토리를 찾을 수 없습니다.");
      return;
    }

    debugPrint("download path: $dir");

    final savePath = dir.path;

    final uri = Uri.parse(url);
    final fileName = uri.queryParameters['vf'] ?? 'downloaded_file.jpg';

    debugPrint("filename: $fileName");
    try {
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savePath,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: true,
        saveInPublicStorage: Platform.isAndroid, // iOS는 반드시 false
      );

      debugPrint('다운로드 작업 등록됨, taskId: $taskId, 파일명: $fileName');
    } catch (e) {
      debugPrint('다운로드 실패: $e');
    }
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (await _controller.canGoBack()) {
          _controller.goBack();
          return false;
        } else {
          if (Platform.isAndroid) {
            SystemNavigator.pop(); // 안드로이드는 네이티브 방식으로 종료
          } else if (Platform.isIOS) {
            exit(0); // iOS는 강제 종료 (애플 가이드라인상 권장되지는 않지만 가능)
          }
          return false;
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

// flutter_downloader 콜백 함수 반드시 static + vm:entry-point 지정 필요
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(
    'downloader_send_port',
  );
  send?.send([id, status, progress]);
}
