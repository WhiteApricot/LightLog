import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/core/occurrence_time.dart';

void main() {
  group('OccurrenceTime', () {
    test('restores wall time with the saved positive offset', () {
      final wallTime = OccurrenceTime.restoreWallTime(
        utcMilliseconds: DateTime.utc(
          2026,
          1,
          1,
          16,
          30,
        ).millisecondsSinceEpoch,
        timezoneOffsetMinutes: 480,
      );

      expect(wallTime, DateTime.utc(2026, 1, 2, 0, 30));
    });

    test('restores wall time with the saved negative offset', () {
      final wallTime = OccurrenceTime.restoreWallTime(
        utcMilliseconds: DateTime.utc(2026, 1, 2, 2, 15).millisecondsSinceEpoch,
        timezoneOffsetMinutes: -300,
      );

      expect(wallTime, DateTime.utc(2026, 1, 1, 21, 15));
    });

    test(
      'round trips wall time independently of the current device timezone',
      () {
        final originalWallTime = DateTime.utc(2026, 6, 8, 9, 7);
        final utcMilliseconds = OccurrenceTime.toUtcMilliseconds(
          wallTime: originalWallTime,
          timezoneOffsetMinutes: 345,
        );

        expect(
          utcMilliseconds,
          DateTime.utc(2026, 6, 8, 3, 22).millisecondsSinceEpoch,
        );
        expect(
          OccurrenceTime.restoreWallTime(
            utcMilliseconds: utcMilliseconds,
            timezoneOffsetMinutes: 345,
          ),
          originalWallTime,
        );
      },
    );
  });
}
