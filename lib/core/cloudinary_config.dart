class CloudinaryConfig {
  static const cloudName = 'x4osfjgq';

  static const avatarUploadPreset = 'criptivo_avatars';
  static const mediaUploadPreset = 'criptivo_media';

  /// auto/upload → image, video, raw
  static String get uploadUrl =>
      'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
}
