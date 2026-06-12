import 'package:flowplanv2/shared/widgets/task_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskBlock worker 11 widget coverage', () {
    testWidgets('short block renders a one-line title and handles taps',
        (tester) async {
      var tapped = 0;

      await _pumpTaskBlock(
        tester,
        TaskBlock(
          key: const ValueKey('tiny-block'),
          top: 8,
          height: 24,
          label: 'Tiny focus',
          color: Colors.yellow,
          onTap: () => tapped++,
        ),
      );

      final title = tester.widget<Text>(find.text('Tiny focus'));
      expect(title.maxLines, 1);
      expect(title.softWrap, isFalse);
      expect(title.style?.color, Colors.black87);

      await tester.tap(find.text('Tiny focus'));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('actual block uses actual styling and cleans blank details',
        (tester) async {
      await _pumpTaskBlock(
        tester,
        const TaskBlock(
          top: 12,
          height: 86,
          label: 'Observed work',
          location: '   ',
          note: 'evidence note',
          durationText: '  ',
          color: Colors.blue,
          isActual: true,
        ),
        brightness: Brightness.dark,
      );

      expect(find.text('Observed work'), findsOneWidget);
      expect(find.text('evidence note'), findsOneWidget);
      expect(find.byType(Text), findsAtLeastNWidgets(3));
      expect(find.textContaining('   '), findsNothing);

      final decorated = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((container) => container.decoration is BoxDecoration);
      final decoration = decorated.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.color, isNotNull);
    });

    testWidgets('dragging reports clamped top and resets visual position',
        (tester) async {
      double? dragEnd;

      await _pumpTaskBlock(
        tester,
        TaskBlock(
          key: const ValueKey('drag-block'),
          top: 40,
          height: 72,
          label: 'Movable task',
          color: Colors.indigo,
          isDraggable: true,
          onDragEnd: (value) => dragEnd = value,
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(
        find.text('Movable task'),
      ));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dragEnd, 0);
      final positioned = _taskPositioned(tester, 'drag-block');
      expect(positioned.top, 42);
    });

    testWidgets('resize handle clamps to minimum height and reports final value',
        (tester) async {
      double? resizedHeight;

      await _pumpTaskBlock(
        tester,
        TaskBlock(
          key: const ValueKey('resize-block'),
          top: 0,
          height: 80,
          label: 'Resizable task',
          color: Colors.green,
          isDraggable: true,
          onResizeEnd: (value) => resizedHeight = value,
        ),
      );

      final handleCenter = tester.getCenter(
        _resizeGestureAreaFinder('resize-block'),
      );
      await tester.dragFrom(handleCenter, const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(resizedHeight, TaskBlock.minHeight);
      final positioned = _taskPositioned(tester, 'resize-block');
      expect(positioned.height, 76);
    });

    testWidgets('updated widget values are ignored during drag but applied after',
        (tester) async {
      const key = ValueKey('changing-block');
      Widget block({required double top, required double height}) {
        return TaskBlock(
          key: key,
          top: top,
          height: height,
          label: 'Changing task',
          color: Colors.purple,
          isDraggable: true,
        );
      }

      await _pumpTaskBlock(tester, block(top: 10, height: 60));
      final gesture = await tester.startGesture(tester.getCenter(
        find.text('Changing task'),
      ));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      await _pumpTaskBlock(tester, block(top: 100, height: 120));
      var positioned = _taskPositioned(tester, 'changing-block');
      expect(positioned.top, 42);
      expect(positioned.height, 56);

      await gesture.up();
      await tester.pumpAndSettle();
      await _pumpTaskBlock(tester, block(top: 100, height: 120));
      positioned = _taskPositioned(tester, 'changing-block');

      expect(positioned.top, 102);
      expect(positioned.height, 116);
    });
  });
}

Future<void> _pumpTaskBlock(
  WidgetTester tester,
  Widget block, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SizedBox(
          width: 260,
          height: 260,
          child: Stack(children: [block]),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Positioned _taskPositioned(WidgetTester tester, String key) {
  return tester
      .widgetList<Positioned>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Positioned),
        ),
      )
      .singleWhere((widget) => widget.top != null && widget.left == 4);
}

Finder _resizeGestureAreaFinder(String key) {
  return find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Positioned &&
          widget.bottom == 0 &&
          widget.height == 12,
    ),
  );
}
