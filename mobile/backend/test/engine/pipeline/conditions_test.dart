import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_backend/engine/pipeline/conditions.dart';

void main() {
  ({Gate gate, int threads}) at({int battery = 80, bool charging = false, bool only = false, int thermal = 0, bool live = false}) =>
      decide(battery: battery, charging: charging, onlyWhileCharging: only, thermal: thermal, live: live);

  test('after Stop: 4 threads', () => expect(at(), (gate: Gate.go, threads: 4)));
  test('while recording: 2 threads', () => expect(at(live: true), (gate: Gate.go, threads: 2)));
  test('warm phone: 2 threads', () => expect(at(thermal: 2), (gate: Gate.go, threads: 2)));
  test('hot phone waits', () => expect(at(thermal: 3).gate, Gate.waitCool));
  test('under 20% not charging waits for charge', () => expect(at(battery: 19).gate, Gate.waitCharge));
  test('20% not charging goes', () => expect(at(battery: 20).gate, Gate.go));
  test('under 20% charging goes', () => expect(at(battery: 5, charging: true).gate, Gate.go));
  test('only while charging, unplugged, waits for charge', () => expect(at(only: true).gate, Gate.waitCharge));
  test('only while charging, plugged in, goes', () => expect(at(only: true, charging: true).gate, Gate.go));
}
