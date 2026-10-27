// Loads the bundled SignBridge logo for PDF appearance streams.

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'appearance.dart';

const logoAssetPath = 'assets/images/logo_stamp.png';

AppearanceLogo? _cachedLogo;

/// Load (and cache) the transparent SignBridge stamp logo.
Future<AppearanceLogo> loadAppearanceLogo() async {
  if (_cachedLogo != null) return _cachedLogo!;
  final data = await rootBundle.load(logoAssetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    throw FormatException('Failed to decode $logoAssetPath');
  }

  final w = decoded.width;
  final h = decoded.height;
  final rgb = Uint8List(w * h * 3);
  final alpha = Uint8List(w * h);
  var ri = 0;
  var ai = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      rgb[ri++] = p.r.toInt();
      rgb[ri++] = p.g.toInt();
      rgb[ri++] = p.b.toInt();
      alpha[ai++] = p.a.toInt();
    }
  }

  _cachedLogo = AppearanceLogo(
    rgbBytes: rgb,
    alphaBytes: alpha,
    pixelWidth: w,
    pixelHeight: h,
  );
  return _cachedLogo!;
}

/// Human-readable local date/time for the visible signature stamp.
String formatAppearanceDateTime(DateTime dt) {
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
}
