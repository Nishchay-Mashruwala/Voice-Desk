import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// The permissions recording needs, by id: `microphone`, `notifications`,
/// `battery_unrestricted` (Samsung and others stop background apps otherwise).
abstract class PermissionsStatus {
  Future<Map<String, bool>> check();
  Future<void> request(String id);

  /// The app's page in Android's settings (when a permission was refused for good).
  Future<void> openSettings();
}

const _permissions = {
  'microphone': Permission.microphone,
  'notifications': Permission.notification,
  'battery_unrestricted': Permission.ignoreBatteryOptimizations,
};

class AndroidPermissions implements PermissionsStatus {
  @override
  Future<Map<String, bool>> check() async => {
        for (final e in _permissions.entries) e.key: await e.value.isGranted,
      };

  @override
  Future<void> request(String id) async {
    await _permissions[id]?.request();
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

final permissionsProvider = Provider<PermissionsStatus>((ref) => AndroidPermissions());
