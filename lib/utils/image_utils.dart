import '../config/api_config.dart';

class ImageUtils {
  static String getFullImageUrl(String? url) {
    return ApiConfig.getUploadUrl(url);
  }
}
