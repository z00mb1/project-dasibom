import '../config/utils.dart';

class MissingListPerson {
  final String msspsnnIdntfccd; // ✅ 추가
  final String name;
  final String gender;
  final int age;
  final String category;
  final String registeredDate;
  final String? photo;
  final String? region;

  MissingListPerson({
    required this.msspsnnIdntfccd,
    required this.name,
    required this.gender,
    required this.age,
    required this.category,
    required this.registeredDate,
    required this.photo,
    this.region,
  });

  factory MissingListPerson.fromJson(Map<String, dynamic> json) {
    return MissingListPerson(
      msspsnnIdntfccd: json['msspsn_idntfccd']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      gender: json['gender_display']?.toString() ??
          json['gender']?.toString() ??
          '',
      age: json['current_age'] is int
          ? json['current_age']
          : int.tryParse(json['current_age']?.toString() ?? '') ??
              int.tryParse(json['age']?.toString() ?? '') ??
              0,
      category: json['category_display']?.toString() ??
          json['category']?.toString() ??
          '',
      registeredDate: json['registered_date']?.toString() ?? '',
      photo: extractPhotoUrl(json['photo'] ?? json['photo_info']),
      region: json['region']?.toString() ??
          json['occurred_location']?.toString() ??
          json['occurred_city']?.toString() ??
          json['sido']?.toString() ??
          json['address_region']?.toString(),
    );
  }
}