class Facility {
  final String id;
  final String name;
  final String categoryName;
  final String code;
  final String type;
  final String address;
  final String tel;
  final double lat;
  final double lng;

  Facility({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.code,
    required this.type,
    required this.address,
    required this.tel,
    required this.lat,
    required this.lng,
  });

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      categoryName: json['categoryName'] ?? '',
      code: json['code'] ?? '',
      type: json['type'] ?? '',
      address: json['address'] ?? '',
      tel: json['tel'] ?? '정보 없음',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}
