import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// May processing run now?
enum Gate { go, waitCharge, waitCool }

/// Below this battery level (not charging) processing waits (owner's value).
const kMinBatteryPercent = 20;

/// Android's thermal status: MODERATE slows down, SEVERE waits.
const kThermalModerate = 2;
const kThermalSevere = 3;

/// Setting: only process while the phone charges.
const kOnlyWhileChargingKey = 'only_while_charging';

/// The rules for processing: wait when hot, or on a low battery (or the
/// "only while charging" setting) when not charging. 2 threads while recording
/// or warm, else 4.
({Gate gate, int threads}) decide({
  required int battery,
  required bool charging,
  required bool onlyWhileCharging,
  required int thermal,
  required bool live,
}) {
  if (thermal >= kThermalSevere) return (gate: Gate.waitCool, threads: 0);
  if (!charging && (onlyWhileCharging || battery < kMinBatteryPercent)) return (gate: Gate.waitCharge, threads: 0);
  return (gate: Gate.go, threads: live || thermal >= kThermalModerate ? 2 : 4);
}

/// The phone's battery and temperature.
abstract class DeviceState {
  Future<int> battery();
  Future<bool> charging();

  /// Android's thermal status (0 none … 6 shutdown).
  Future<int> thermal();

  /// Fires when charging starts or stops.
  Stream<void> get changes;
}

class PhoneDeviceState implements DeviceState {
  final _battery = Battery();
  static const _channel = MethodChannel('voicedesk/device');

  @override
  Future<int> battery() => _battery.batteryLevel;

  @override
  Future<bool> charging() async => switch (await _battery.batteryState) {
        BatteryState.charging || BatteryState.full || BatteryState.connectedNotCharging => true,
        _ => false,
      };

  @override
  Future<int> thermal() async => await _channel.invokeMethod<int>('thermalStatus') ?? 0;

  @override
  Stream<void> get changes => _battery.onBatteryStateChanged.map((_) {});
}

final deviceStateProvider = Provider<DeviceState>((ref) => PhoneDeviceState());
