import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';

class GuardianLocationMap extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final Color cardBgColor;

  const GuardianLocationMap({
    super.key,
    required this.profile,
    required this.cardBgColor,
  });

  @override
  State<GuardianLocationMap> createState() => _GuardianLocationMapState();
}

class _GuardianLocationMapState extends State<GuardianLocationMap> {
  late final WebViewController _mapWebController;

  double? _lat;
  double? _lng;
  bool _mapReady = false;
  bool _mapLoaded = false;
  WebSocketChannel? _gpsChannel;
  Timer? _reconnectTimer;
  Timer? _clockTimer;   // "N분 전" 텍스트 주기 갱신
  bool _manualClose = false;

  DateTime? _gpsTimestamp;   // API에서 받은 마지막 위치 시각
  bool _locationTooOld = false; // 24시간 이상 지난 경우
  bool _noLocationData = false; // GPS 데이터 아예 없음

  @override
  void initState() {
    super.initState();

    _mapWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'OnBadgeMapReady',
        onMessageReceived: (_) {
          _mapReady = true;
          final lat = _lat;
          final lng = _lng;
          if (lat != null && lng != null) {
            _mapWebController.runJavaScript('moveBadgeLocation($lat, $lng);');
          }
        },
      );

    final code = _currentDeviceCode(widget.profile);
    debugPrint('[LocationMap] initState → device_code=$code');
    if (code != null) {
      _startGpsTracking();
    }
  }

  Future<void> _startGpsTracking() async {
    _manualClose = false;

    await _fetchBadgeLocation();
    _connectGpsWebSocket();

    // "N분 전" 텍스트를 1분마다 자동 갱신
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && (_noLocationData || _locationTooOld)) {
        setState(() {});
      }
    });
  }

  void _loadMap(double lat, double lng) {
    setState(() => _mapLoaded = true);
    _mapWebController.loadHtmlString(
      _getKakaoMapHtml(lat, lng),
      baseUrl: 'http://localhost/',
    );
  }

  void _connectGpsWebSocket() {
    final deviceCode = _currentDeviceCode(widget.profile);

    if (deviceCode == null) {
      debugPrint('device_code가 없어 GPS WebSocket을 연결하지 않습니다.');
      return;
    }

    _gpsChannel?.sink.close();

    final wsUrl =
        'wss://dasibom-m9c3.onrender.com/ws/gps/${Uri.encodeComponent(deviceCode)}/';

    debugPrint('[LocationMap] GPS WebSocket 연결 시도: $wsUrl');

    try {
      _gpsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _gpsChannel!.stream.listen(
        (message) {
          final decoded = jsonDecode(message);

          if (decoded is! Map) return;

          if (decoded['type'] == 'connected') {
            debugPrint('GPS WebSocket 연결 성공');
            return;
          }

          if (decoded['type'] != 'gpsLocation') return;

          final data = decoded['data'];
          if (data is! Map) return;

          final lat = double.tryParse(data['lat'].toString());
          final lng = double.tryParse(data['lng'].toString());

          if (lat == null || lng == null) return;
          if (!mounted) return;

          debugPrint('★★★ [LocationMap] WS 위치 lat=$lat, lng=$lng, device=${_currentDeviceCode(widget.profile)}');

          final now = DateTime.now();
          final wasOld = _locationTooOld || _noLocationData;

          setState(() {
            _lat = lat;
            _lng = lng;
            _gpsTimestamp = now;
            _locationTooOld = false;
            _noLocationData = false;
          });

          if (wasOld && !_mapLoaded) {
            _loadMap(lat, lng);
          } else if (_mapReady) {
            _mapWebController.runJavaScript('moveBadgeLocation($lat, $lng);');
          }
        },
        onError: (error) {
          debugPrint('GPS WebSocket 오류: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('GPS WebSocket 연결 종료');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('GPS WebSocket 연결 실패: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualClose) return;

    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _connectGpsWebSocket();
    });
  }

  @override
  void didUpdateWidget(covariant GuardianLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCode = _currentDeviceCode(oldWidget.profile);
    final newCode = _currentDeviceCode(widget.profile);

    if (oldCode != newCode) {
      _manualClose = true;
      _gpsChannel?.sink.close();
      _reconnectTimer?.cancel();
      _clockTimer?.cancel();

      // 이전 지도 상태 완전 리셋
      _mapReady = false;
      _mapLoaded = false;
      _lat = null;
      _lng = null;
      _gpsTimestamp = null;
      _locationTooOld = false;
      _noLocationData = false;

      if (newCode != null) {
        _startGpsTracking();
      } else {
        if (mounted) setState(() => _noLocationData = true);
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[LocationMap] dispose → device_code=${_currentDeviceCode(widget.profile)}');

    _manualClose = true;
    _reconnectTimer?.cancel();
    _clockTimer?.cancel();
    _gpsChannel?.sink.close();
    super.dispose();
  }

  Future<void> refresh() async {
    await _fetchBadgeLocation();
  }

  Future<void> _fetchBadgeLocation() async {
    final deviceCode = _currentDeviceCode(widget.profile);
    debugPrint('[LocationMap] _fetchBadgeLocation → device_code=$deviceCode');

    if (deviceCode == null) {
      _manualClose = true;
      _gpsChannel?.sink.close();
      _reconnectTimer?.cancel();
      if (mounted) setState(() => _noLocationData = true);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/gps/latest/?device_code=${Uri.encodeComponent(deviceCode)}',
        ),
        headers: {
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      final body = utf8.decode(response.bodyBytes);

      debugPrint('뱃지 위치 조회 코드: ${response.statusCode}');
      debugPrint('뱃지 위치 조회 바디: $body');

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() => _noLocationData = true);
        return;
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        setState(() => _noLocationData = true);
        return;
      }

      final lat = double.tryParse(
        (decoded['lat'] ?? decoded['latitude'])?.toString() ?? '',
      );
      final lng = double.tryParse(
        (decoded['lng'] ?? decoded['longitude'])?.toString() ?? '',
      );

      if (lat == null || lng == null) {
        setState(() => _noLocationData = true);
        return;
      }

      // timestamp 파싱
      final rawTs = decoded['timestamp']?.toString()
          ?? decoded['created_at']?.toString()
          ?? decoded['recorded_at']?.toString()
          ?? '';
      DateTime? ts;
      if (rawTs.isNotEmpty) {
        try { ts = DateTime.parse(rawTs).toLocal(); } catch (_) {}
      }

      final tooOld = ts != null && DateTime.now().difference(ts).inHours >= 24;

      setState(() {
        _lat = lat;
        _lng = lng;
        _gpsTimestamp = ts;
        _locationTooOld = tooOld;
        _noLocationData = false;
      });

      debugPrint('★★★ [LocationMap] HTTP 위치 lat=$lat, lng=$lng, ts=$rawTs, device=$deviceCode');

      if (!_mapLoaded) {
        _loadMap(lat, lng);
      } else if (_mapReady) {
        _mapWebController.runJavaScript('moveBadgeLocation($lat, $lng);');
      }
    } catch (e) {
      debugPrint('뱃지 위치 조회 에러: $e');
      if (mounted) setState(() => _noLocationData = true);
    }
  }

  String? _currentDeviceCode(Map<String, dynamic>? profile) {
    if (profile == null) return null;

    final device = profile['device'];

    if (device is Map) {
      final deviceUid =
          device['device_uid'] ??
          device['device_code'] ??
          device['uid'] ??
          device['code'];

      final text = deviceUid?.toString().trim();

      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }

    final candidates = [
      profile['device_code'],
      profile['deviceCode'],
      profile['badge_code'],
      profile['gps_device_code'],
      profile['device_uid'],
    ];

    for (final value in candidates) {
      final text = value?.toString().trim();

      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }

    debugPrint('deviceCode 확인: null');
    return null;
  }

  String _display(dynamic value, {String fallback = '피보호자'}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final profileName = _display(widget.profile?['name']);

    return Container(
      decoration: BoxDecoration(
        color: widget.cardBgColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.explore_outlined, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$profileName님의 실시간 위치',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(15),
              bottomRight: Radius.circular(15),
            ),
            child: SizedBox(
              height: 220,
              child: _noLocationData
                  ? _buildNoLocationUI()
                  : _mapLoaded
                      ? Stack(
                          children: [
                            WebViewWidget(
                              controller: _mapWebController,
                              gestureRecognizers: {
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              },
                            ),
                            if (_locationTooOld && _gpsTimestamp != null)
                              _buildStaleDataBanner(),
                          ],
                        )
                      : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoLocationUI() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              '최근 위치 정보가 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              '뱃지가 GPS 신호를 수신하면 자동으로 표시됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaleDataBanner() {
    final diff = DateTime.now().difference(_gpsTimestamp!);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final timeStr = h > 0 ? '$h시간 $m분' : '$m분';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        color: Colors.black.withValues(alpha: 0.55),
        child: Text(
          '마지막 위치 기준 · $timeStr 전 데이터',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }

  String _getKakaoMapHtml(double lat, double lng) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
      <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=ca87ffa359c7f5886afe0fac4dab4225&autoload=false"></script>
      <style>
        html, body, #map { width:100%; height:100%; margin:0; padding:0; }
        .badge-dot {
          width: 18px;
          height: 18px;
          background: #F44336;
          border: 3px solid white;
          border-radius: 50%;
          box-shadow: 0 0 8px rgba(244, 67, 54, 0.8);
        }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <script>
        var map;
        var badgeMarker;

        kakao.maps.load(function() {
          var container = document.getElementById('map');
          var initialPosition = new kakao.maps.LatLng($lat, $lng);

          map = new kakao.maps.Map(container, {
            center: initialPosition,
            level: 3
          });

          var dotContent = '<div class="badge-dot"></div>';

          badgeMarker = new kakao.maps.CustomOverlay({
            position: initialPosition,
            content: dotContent,
            yAnchor: 0.5,
            xAnchor: 0.5
          });

          badgeMarker.setMap(map);

          if (window.OnBadgeMapReady) {
            OnBadgeMapReady.postMessage('ready');
          }
        });

        function moveBadgeLocation(lat, lng) {
          var pos = new kakao.maps.LatLng(lat, lng);

          if (map) {
            map.setCenter(pos);
          }

          if (badgeMarker) {
            badgeMarker.setPosition(pos);
            badgeMarker.setMap(map);
          }
        }
      </script>
    </body>
    </html>
    ''';
  }
}