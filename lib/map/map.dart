import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../config/api_config.dart'; // 경로는 본인 프로젝트에 맞게


import 'facility.dart';


class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final WebViewController _controller; // ✅ late final로 변경
  
  late String redMarker;
  late String blueMarker;

  String _selectedCategory = "시설을 선택해주세요";
  String _selectedCode = "";
  String _selectedFacilityType = "";
  String _selectedAddress = "지도에서 마커를 클릭해보세요";
  String _selectedTel = "-";
  bool _manualSearchDone = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController(); // ✅ 여기서 초기화
    _initMarkers();
  }

  Future<String> _getSvgBase64WithColor(String path, Color color) async {
    try {
      String svgString = await rootBundle.loadString(path);

      String colorHex =
          '#${color.toARGB32().toRadixString(16).substring(2)}';

      String coloredSvg = svgString.replaceAll(
        RegExp(r'#000000|black', caseSensitive: false),
        colorHex,
      );

      if (!coloredSvg.contains('fill=')) {
        coloredSvg = coloredSvg.replaceAll(
          '<path',
          '<path fill="$colorHex"',
        );
      }

      return "data:image/svg+xml;base64,${base64Encode(utf8.encode(coloredSvg))}";
    } catch (e) {
      debugPrint("❌ SVG 로드 실패: $e");
      return "";
    }
  }

  Future<void> _initMarkers() async {
    redMarker = await _getSvgBase64WithColor(
      "assets/icons/location.svg",
      Colors.red,
    );

    blueMarker = await _getSvgBase64WithColor(
      "assets/icons/location.svg",
      Colors.blue,
    );

    _loadHtmlFromAssets();
  }

  Future<void> _loadHtmlFromAssets() async {
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
        ),
      )
      ..addJavaScriptChannel(
        'OnMarkerClick',
        onMessageReceived: (message) {
          if (!mounted) return;
          final data = jsonDecode(message.message);
          setState(() {
            _selectedCode = data['clCode'] ?? "";
            _selectedFacilityType = data['facilityType'] ?? "";
            _selectedCategory = data['clNm'] ?? "-";
            _selectedAddress = data['address'] ?? "-";
            _selectedTel = data['tel'] ?? "-";
          });
        },
      )
      ..addJavaScriptChannel(
        'OnMapReady',
        onMessageReceived: (_) {
          _getMyLocation();
        },
      )
      ..addJavaScriptChannel(
  'OnCenterChanged',
  onMessageReceived: (message) {
    if (!mounted) return;

    final data = jsonDecode(message.message);

    final centerLat = (data['lat'] as num).toDouble();
    final centerLng = (data['lng'] as num).toDouble();
    final level = (data['level'] as num?)?.toInt() ?? 5;

    _manualSearchDone = true;

    _controller.runJavaScript("clearMarkers();");

    _fetchFacilities(
      centerLat,
      centerLng,
      radiusKm: _levelToRadius(level),
    );
  },
)
      ..loadHtmlString(
        _getKakaoMapHtml(redMarker, blueMarker),
        baseUrl: 'http://localhost/',
      );
  }

  String _getKakaoMapHtml(String imgRed, String imgBlue) {
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>다시봄 지도</title>
    <script type="text/javascript" src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=ca87ffa359c7f5886afe0fac4dab4225&autoload=false"></script>
    <style>
        html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden; background-color: white; }
        .label {
            margin-bottom: 65px; 
            background-color: white;
            border: 1px solid #888;
            border-radius: 5px;
            padding: 5px 10px;
            font-size: 13px;
            font-weight: bold;
            text-align: center;
            white-space: nowrap; 
            box-shadow: 2px 2px 5px rgba(0,0,0,0.3);
            position: relative;
        }
        .label:after {
            content: '';
            position: absolute;
            bottom: -5px;
            left: 50%;
            margin-left: -5px;
            width: 10px;
            height: 10px;
            background: white;
            border-bottom: 1px solid #888;
            border-right: 1px solid #888;
            transform: rotate(45deg);
        }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        function addMyLocationMarker(lat, lng) {
            var position = new kakao.maps.LatLng(lat, lng);

            var marker = new kakao.maps.Marker({
                position: position,
                map: map
            });

            // 🔥 파란 원 (내 위치 느낌)
            var circle = new kakao.maps.Circle({
                center: position,
                radius: 30,
                strokeWeight: 2,
                strokeColor: '#007BFF',
                strokeOpacity: 0.8,
                fillColor: '#007BFF',
                fillOpacity: 0.3
            });

            circle.setMap(map);
        }

        var map;
        var markers = []; 
        var currentOverlay = null; 

        var imgRed = "$imgRed"; 
        var imgBlue = "$imgBlue"; 

            function initMap() {
                kakao.maps.load(function() {
                    var container = document.getElementById('map');
                    var options = {
                        center: new kakao.maps.LatLng(37.5665, 126.9780),
                        level: 3
                    };
                    map = new kakao.maps.Map(container, options);

                    if (window.OnMapReady) {
                        OnMapReady.postMessage('ready');
                    }
                });
            }

            initMap();   // 🔥🔥🔥 이거 추가

        function clearMarkers() {
            for (var i = 0; i < markers.length; i++) {
                markers[i].setMap(null); 
            }
            markers = []; 
            if (currentOverlay) {
                currentOverlay.setMap(null);
                currentOverlay = null;
            }
        }

        function getMarkerImage(clCode, facilityType) {
            var imageSrc = imgBlue;
            if (clCode === "16" || clCode === "20" || facilityType === "danger") {
                imageSrc = imgRed;
            }
            var imageSize = new kakao.maps.Size(45, 60);
            return new kakao.maps.MarkerImage(imageSrc, imageSize);
        }

        function moveToLocation(lat, lng) {
            if(map) {
                var moveLatLon = new kakao.maps.LatLng(lat, lng);
                map.setCenter(moveLatLon);
            }
        }

        function getMapCenter() {
            if(map) {
                var center = map.getCenter();
                var data = {
                    lat: center.getLat(),
                    lng: center.getLng(),
                    level: map.getLevel()
                };
                OnCenterChanged.postMessage(JSON.stringify(data));
            }
        }

        function addMarkerFromApp(jsonString) {
            try {
                var data = JSON.parse(jsonString);
                if (map) {
                    var position = new kakao.maps.LatLng(data.lat, data.lng);
                    var markerImage = getMarkerImage(data.clCode, data.facilityType);
                    var marker = new kakao.maps.Marker({
                        position: position,
                        image: markerImage,
                        map: map
                    });
                    markers.push(marker);
                    kakao.maps.event.addListener(marker, 'click', function() {
                        if (currentOverlay) {
                            currentOverlay.setMap(null);
                        }
                        var content = '<div class="label">' + data.clNm + '</div>';
                        var customOverlay = new kakao.maps.CustomOverlay({
                            position: position,
                            content: content,
                            yAnchor: 1 
                        });
                        customOverlay.setMap(map);
                        currentOverlay = customOverlay; 
                        var info = {
                            type: 'click',
                            clCode: data.clCode,
                            facilityType: data.facilityType,
                            clNm: data.clNm,
                            address: data.address,
                            tel: data.tel
                        };
                        OnMarkerClick.postMessage(JSON.stringify(info));
                    });
                }
            } catch (e) { }
        }
    </script>
</body>
</html>
    ''';
  }

  // 나머지 위젯(_getMyLocation, build, _categoryBadge 등)은 기존과 동일하므로 생략하지만, 
  // 실제 코드에서는 반드시 그대로 두셔야 합니다.

  Future<void> _getMyLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // 1. 마지막 위치로 일단 빠르게 시작
    try {
      Position? last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && !_manualSearchDone) {
        _controller.runJavaScript("moveToLocation(${last.latitude}, ${last.longitude})");
        _controller.runJavaScript("addMyLocationMarker(${last.latitude}, ${last.longitude})");
        _fetchFacilities(last.latitude, last.longitude);
      }
    } catch (_) {}

    // 2. 정확한 위치 받으면 업데이트
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.lowest,
          timeLimit: Duration(seconds: 30),
        ),
      );
      if (!mounted || _manualSearchDone) return;
      _controller.runJavaScript("moveToLocation(${position.latitude}, ${position.longitude})");
      _controller.runJavaScript("addMyLocationMarker(${position.latitude}, ${position.longitude})");
      _fetchFacilities(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("위치 불러오기 실패(기본값 사용): $e");
      // getLastKnownPosition도 없고 getCurrentPosition도 실패한 경우에만 도달
      // lastKnownPosition이 있었다면 이미 위에서 지도가 이동된 상태이므로 추가 이동 불필요
    }
  }

  double _levelToRadius(int level) {
    if (level <= 3) return 1.0;
    if (level <= 4) return 2.0;
    if (level <= 5) return 3.0;
    if (level <= 6) return 5.0;
    return 8.0;
  }

  Future<void> _fetchFacilities(double lat, double lng, {double radiusKm = 2.0}) async {
  final url = Uri.parse(
    "${ApiConfig.baseUrl}/facilities/?lat=$lat&lng=$lng&radius=$radiusKm");
  
  try {
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      debugPrint("받은 시설 수: ${(jsonData['data'] as List).length}"); // ✅ 여기
      debugPrint("코드 목록: ${(jsonData['data'] as List).map((e) => e['code']).toSet()}"); // ✅ 여기
    
      List<Facility> facilities =
          (jsonData['data'] as List).map((e) => Facility.fromJson(e)).toList();

      for (Facility f in facilities) {
        var data = {
          "lat": f.lat,
          "lng": f.lng,
          "clCode": f.code,
          "facilityType": f.type,
          "clNm": f.categoryName,
          "address": f.address,
          "tel": f.tel
        };

        String jsonString = jsonEncode(data);

        _controller.runJavaScript(
          "addMarkerFromApp('$jsonString');"
        );
      }
    }
  } catch (e) {
    debugPrint("시설 조회 실패: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFEF9),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, size: 28),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
                    child: Image.asset("assets/images/dasibom_logo.png", height: 40),
                  ),
                  const SizedBox(width: 28),
                ],
              ),
            ),

            Expanded(
              child: Stack(
                children: [
                  // 1. 지도는 항상 바닥에 깔아둡니다. (삼항 연산자로 없애지 않음)
                  WebViewWidget(controller: _controller),
                
                  
                  // 범례
                  Positioned(
                    top: 10, left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legend(Icons.place, Colors.red, "위험시설"),
                          const SizedBox(height: 6),
                          _legend(Icons.place, Colors.blue, "안전시설"),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 정보창
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFEF9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)), 
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _categoryBadge(), 
                      ElevatedButton.icon(
                        onPressed: () {
                            _controller.runJavaScript("getMapCenter()");
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFCF6D6), 
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text("현 지도 위치로 재검색", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("주소", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _inputBox(_selectedAddress),
                  const SizedBox(height: 16),
                  const Text("전화번호", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _inputBox(_selectedTel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryBadge() {
    bool isDanger = (_selectedCode == "16" || _selectedCode == "20") ||
        _selectedFacilityType == "danger";
    Color color = isDanger ? Colors.red : Colors.blue;
    IconData icon = isDanger ? Icons.warning_amber_rounded : Icons.verified_user_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha:0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            _selectedCategory,
            style: TextStyle(
              color: color, 
              fontWeight: FontWeight.bold,
              fontSize: 13
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D8), 
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }

  Widget _legend(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}