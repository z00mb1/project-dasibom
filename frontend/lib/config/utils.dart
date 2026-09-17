String? extractPhotoUrl(dynamic photo) {
  if (photo == null) return null;

  if (photo is String) {
    return photo.isNotEmpty ? photo : null;
  }

  if (photo is Map) {
    return (photo['url'] ??
            photo['image'] ??
            photo['image_url'] ??
            photo['photo'])
        ?.toString();
  }

  if (photo is List && photo.isNotEmpty) {
    return extractPhotoUrl(photo.first);
  }

  return null;
}