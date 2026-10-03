import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<TimeOfDay?> showWheelTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  final hourController = FixedExtentScrollController(
    initialItem: initialTime.hour,
  );
  final minuteController = FixedExtentScrollController(
    initialItem: initialTime.minute,
  );
  var hour = initialTime.hour;
  var minute = initialTime.minute;

  final result = await showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: 310,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Text(
                    '选择时间（24 小时制）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      TimeOfDay(hour: hour, minute: minute),
                    ),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 88,
                    child: CupertinoPicker.builder(
                      scrollController: hourController,
                      itemExtent: 44,
                      useMagnifier: true,
                      magnification: 1.12,
                      childCount: 24,
                      onSelectedItemChanged: (value) => hour = value,
                      itemBuilder: (_, index) =>
                          Center(child: Text(index.toString().padLeft(2, '0'))),
                    ),
                  ),
                  Text(':', style: Theme.of(context).textTheme.headlineMedium),
                  SizedBox(
                    width: 88,
                    child: CupertinoPicker.builder(
                      scrollController: minuteController,
                      itemExtent: 44,
                      useMagnifier: true,
                      magnification: 1.12,
                      childCount: 60,
                      onSelectedItemChanged: (value) => minute = value,
                      itemBuilder: (_, index) =>
                          Center(child: Text(index.toString().padLeft(2, '0'))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  hourController.dispose();
  minuteController.dispose();
  return result;
}
