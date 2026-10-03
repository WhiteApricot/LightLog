class OccurrenceTime {
  const OccurrenceTime._();

  static DateTime restoreWallTime({
    required int utcMilliseconds,
    required int timezoneOffsetMinutes,
  }) {
    _validateOffset(timezoneOffsetMinutes);
    return DateTime.fromMillisecondsSinceEpoch(
      utcMilliseconds,
      isUtc: true,
    ).add(Duration(minutes: timezoneOffsetMinutes));
  }

  static int toUtcMilliseconds({
    required DateTime wallTime,
    required int timezoneOffsetMinutes,
  }) {
    _validateOffset(timezoneOffsetMinutes);
    final wallTimeAsUtc = DateTime.utc(
      wallTime.year,
      wallTime.month,
      wallTime.day,
      wallTime.hour,
      wallTime.minute,
      wallTime.second,
      wallTime.millisecond,
      wallTime.microsecond,
    );
    return wallTimeAsUtc
        .subtract(Duration(minutes: timezoneOffsetMinutes))
        .millisecondsSinceEpoch;
  }

  static void _validateOffset(int offsetMinutes) {
    if (offsetMinutes < -840 || offsetMinutes > 840) {
      throw ArgumentError.value(
        offsetMinutes,
        'timezoneOffsetMinutes',
        '必须位于 -840..840',
      );
    }
  }
}
