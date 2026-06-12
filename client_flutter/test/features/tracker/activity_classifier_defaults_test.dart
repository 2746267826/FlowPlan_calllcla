import 'package:flowplanv2/features/tracker/services/activity_classifier.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/features/tracker/tracker_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WindowSnapshot snapshot({
    String processName = 'unknown.exe',
    String className = 'MainWindow',
    String windowTitle = 'Untitled',
    bool isFullscreen = false,
  }) {
    return WindowSnapshot(
      processName: processName,
      className: className,
      windowTitle: windowTitle,
      isFullscreen: isFullscreen,
      timestamp: DateTime(2026, 6, 10, 9),
    );
  }

  group('ActivityClassifier', () {
    test('classification toString formats category label and confidence', () {
      const classification = ActivityClassification(
        category: 'coding',
        label: 'Editor',
        confidence: 0.876,
      );

      expect(classification.toString(), 'coding / Editor (87%)');
    });

    test('user rules override defaults and respect title patterns', () {
      final classifier = ActivityClassifier()
        ..setUserRules(<ClassificationRule>[
          const ClassificationRule(
            processPattern: 'chrome',
            titlePattern: 'design review',
            category: 'meeting',
            label: 'Design review',
            isDnd: true,
          ),
        ]);

      final matched = classifier.classify(
        snapshot(
          processName: 'Chrome.exe',
          windowTitle: 'Design Review notes',
        ),
      );
      expect(matched.category, 'meeting');
      expect(matched.label, 'Design review');
      expect(matched.confidence, 1);
      expect(matched.isDnd, isTrue);

      final defaultRule = classifier.classify(
        snapshot(
          processName: 'Chrome.exe',
          windowTitle: 'Inbox',
        ),
      );
      expect(defaultRule.category, '\u6d4f\u89c8\u7f51\u9875');
      expect(defaultRule.label, 'Chrome');
      expect(defaultRule.confidence, 0.9);
      expect(defaultRule.isDnd, isFalse);
    });

    test('fullscreen default and known DND app report focus state', () {
      final classifier = ActivityClassifier();

      final unknownFullscreen = classifier.classify(
        snapshot(
          processName: 'MysteryGame.exe',
          isFullscreen: true,
        ),
      );
      expect(unknownFullscreen.category, '\u6e38\u620f');
      expect(unknownFullscreen.label, 'MysteryGame.exe');
      expect(unknownFullscreen.confidence, 0.5);
      expect(unknownFullscreen.isDnd, isTrue);

      final knownDnd = classifier.classify(
        snapshot(processName: 'Riot Valorant Client.exe'),
      );
      expect(knownDnd.category, '\u6e38\u620f');
      expect(knownDnd.isDnd, isTrue);
    });

    test('Android classification keeps known rules and app-label fallback', () {
      final classifier = ActivityClassifier();

      final known = classifier.classifyAndroidApp(
        packageName: 'com.google.android.apps.chrome.exe',
        appLabel: 'Chrome Mobile',
        className: 'Main',
        timestamp: DateTime(2026, 6, 10, 10),
      );
      expect(known.label, 'Chrome');
      expect(known.confidence, greaterThan(0));

      final unknown = classifier.classifyAndroidApp(
        packageName: 'com.example.deep.work',
        appLabel: '  Deep Work  ',
      );
      expect(unknown.category, '\u672a\u5206\u7c7b');
      expect(unknown.label, 'Deep Work');
      expect(unknown.confidence, 0);

      final unlabeled = classifier.classifyAndroidApp(
        packageName: 'com.example.blank',
        appLabel: '   ',
      );
      expect(unlabeled.label, 'com.example.blank');
    });
  });

  group('tracker defaults', () {
    test('self exclusion checks process and title boundaries', () {
      expect(
        isTrackerSelfExcludedWindow(
          processName: ' FlowPlanV2.exe ',
          windowTitle: 'Calendar',
        ),
        isTrue,
      );
      expect(
        isTrackerSelfExcludedWindow(
          processName: 'Code.exe',
          windowTitle: 'FlowPlanV2 settings',
        ),
        isTrue,
      );
      expect(
        isTrackerSelfExcludedWindow(
          processName: 'Code.exe',
          windowTitle: 'Flow planning notes',
        ),
        isFalse,
      );
      expect(
        isTrackerSelfExcludedWindow(
          processName: null,
          windowTitle: null,
        ),
        isFalse,
      );
    });

    test('Android ignored packages reject empty and launcher packages only',
        () {
      expect(isAndroidTrackerIgnoredPackage(null), isTrue);
      expect(isAndroidTrackerIgnoredPackage('   '), isTrue);
      expect(isAndroidTrackerIgnoredPackage(' COM.FLOWPLANV2.APP '), isTrue);
      expect(isAndroidTrackerIgnoredPackage('com.android.launcher3'), isTrue);
      expect(isAndroidTrackerIgnoredPackage('com.example.work'), isFalse);
    });
  });

  group('WindowSnapshot', () {
    test('context comparison ignores title changes but not process or class',
        () {
      final first = snapshot(
        processName: 'Code.exe',
        className: 'Chrome_WidgetWin_1',
        windowTitle: 'file_a.dart',
      );

      expect(
        first.isSameContext(
          snapshot(
            processName: 'Code.exe',
            className: 'Chrome_WidgetWin_1',
            windowTitle: 'file_b.dart',
            isFullscreen: true,
          ),
        ),
        isTrue,
      );
      expect(
        first.isSameContext(
          snapshot(
            processName: 'Code.exe',
            className: 'OtherClass',
            windowTitle: 'file_a.dart',
          ),
        ),
        isFalse,
      );
      expect(
        first.isSameContext(
          snapshot(
            processName: 'code.exe',
            className: 'Chrome_WidgetWin_1',
            windowTitle: 'file_a.dart',
          ),
        ),
        isFalse,
      );
    });
  });
}
