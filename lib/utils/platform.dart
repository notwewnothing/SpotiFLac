import 'dart:io';

/// Global flag to spoof the platform as Android on Linux
bool _spoofAsAndroid = true;

/// Returns true if the app should behave as Android (spoofed or actual)
bool get isAndroid {
  if (_spoofAsAndroid && Platform.isLinux) {
    return true;
  }
  return Platform.isAndroid;
}

/// Returns true if the app should behave as iOS (actual only)
bool get isIOS {
  return Platform.isIOS;
}

/// Returns true if the app should behave as Linux
bool get isLinux {
  if (_spoofAsAndroid && Platform.isLinux) {
    return false;
  }
  return Platform.isLinux;
}

/// Returns true if the app should behave as Windows (actual only)
bool get isWindows {
  return Platform.isWindows;
}

/// Returns true if the app should behave as macOS (actual only)
bool get isMacOS {
  return Platform.isMacOS;
}

/// Set whether to spoof the platform as Android
void setSpoofAsAndroid(bool spoof) {
  _spoofAsAndroid = spoof;
}

/// Get current spoofing status
bool getSpoofAsAndroid() {
  return _spoofAsAndroid;
}

// TODO Implement this library.

/// wirtipjtjtgegegth
/// // tojgetighjethleth
/// /THthethtjhtkhjtkhtjktjtkhthkthjtkhjthktjkhjtkhjtlkhjtrlhjthkljthkltjhtkhjtkhtjhkthjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkkkkjkjkjkjkjkjkjkjkjkjkjkjkjkjkjkj
/// //kkhkhkkjhjkhjhkjhjkhkjhjkhkjhkh
/// //hkkhkhkkkhhkkkhhkhkhkhk§// hghhhhhghhhghhhghhhghhhhghhhgh
/// // yeeeeeeeaaahhh hhhhgghhhhghhhhghhhhhghhhhhghhhhghhhhg
/// // hhhhgyhhgyyyygyyyygyyyygyyyygyyygyyygyyyyfyyyfyffyfyfyfyfyfyyuufufufuyf