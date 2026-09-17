import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_options.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'home/home.dart';
import 'map/map.dart';
import 'guardian/guardian.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);

  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final bool isGuest = prefs.getBool('isGuest') ?? false;
  final String role = prefs.getString('role') ?? 'guest';

  final String initialRoute;
  if (!isLoggedIn && !isGuest) {
    initialRoute = '/login';
  } else if (role == 'guardian') {
    initialRoute = '/guardian';
  } else {
    initialRoute = '/home';
  }

  KakaoSdk.init(nativeAppKey: "d49a0d0babeeaf7ec940e01e2101d33e");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(DasibomApp(initialRoute: initialRoute, isGuest: isGuest));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── 긴급신고 WebSocket 싱글톤 ─────────────────────────────────────────────
class EmergencyService {
  EmergencyService._();
  static final EmergencyService instance = EmergencyService._();

  WebSocketChannel? _channel;

  Future<void> startIfAdmin() async {
    if (_channel != null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('role') == 'admin') _connect();
  }

  void stop() {
    _channel?.sink.close();
    _channel = null;
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://dasibom-m9c3.onrender.com/ws/emergency/'),
      );
      _channel!.ready.then((_) {
        debugPrint('긴급신고 WS 연결 성공');
      }).catchError((e) {
        debugPrint('긴급신고 WS 연결 실패: $e');
        _channel = null;
      });
      _channel!.stream.listen(
        (event) {
          try {
            final payload = jsonDecode(event.toString());
            if (payload is! Map) return;
            debugPrint('긴급신고 WS 원본: $payload');
            if (payload['type']?.toString() != 'emergencyReceived') return;
            // 중첩 data 필드가 없으면 payload 자체를 data로 사용
            final data = (payload['data'] is Map) ? payload['data'] as Map : payload;
            final targetName =
                (data['targetName'] ?? data['ward_name'])?.toString() ?? '알 수 없음';
            final rawKioskNumber =
                (
                  data['kioskNumber'] ??
                  data['kiosk_number'] ??
                  data['deviceCode'] ??
                  data['deviceId']
                )?.toString() ?? '';

            final kioskNumber = formatKioskNumber(rawKioskNumber);

            debugPrint('긴급신고 이벤트 수신: $targetName / $kioskNumber');
            _showDialog(targetName, kioskNumber);
          } catch (e) {
            debugPrint('긴급신고 WS 파싱 오류: $e');
          }
        },
        onError: (e) {
          debugPrint('긴급신고 WS 오류: $e');
          _channel = null;
        },
        onDone: () {
          debugPrint('긴급신고 WS 연결 종료');
          _channel = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('긴급신고 WS 연결 예외: $e');
      _channel = null;
    }
  }

  String formatKioskNumber(String value) {
    if (value.startsWith('KIOSK_')) {
      final number = value.split('_').last;
      return '${int.tryParse(number) ?? number}번';
    }
    return value;
  }

  void _showDialog(String targetName, String kioskNumber) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('긴급신고: context null, 다이얼로그 표시 불가');
      return;
    }
    showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: Colors.red.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
              SizedBox(width: 8),
              Text('긴급신고 발생!',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kioskNumber.isNotEmpty
                    ? '$kioskNumber 키오스크에서 긴급신고가 발생했습니다.'
                    : '키오스크에서 긴급신고가 발생했습니다.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('확인',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
  }
}

class DasibomApp extends StatefulWidget {
  final String initialRoute;
  final bool isGuest;

  const DasibomApp({super.key, required this.initialRoute, required this.isGuest});

  @override
  State<DasibomApp> createState() => _DasibomAppState();
}

class _DasibomAppState extends State<DasibomApp> {
  @override
  void initState() {
    super.initState();
    EmergencyService.instance.startIfAdmin();
  }

  @override
  void dispose() {
    EmergencyService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      debugShowCheckedModeBanner: false,
      title: '다시봄',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFF8E1)),
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      initialRoute: widget.initialRoute,
      routes: {
        '/login': (context) => const Login(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => HomeDashboard(isGuest: widget.isGuest),
        '/guardian': (context) => const GuardianPage(),
        '/map': (context) => const MapPage(),
      },
    );
  }
}
