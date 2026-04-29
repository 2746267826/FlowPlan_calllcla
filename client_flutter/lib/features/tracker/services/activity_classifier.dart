import 'window_sensor.dart';

class ActivityClassification {
  final String category;
  final String label;
  final double confidence;
  final bool isDnd;

  const ActivityClassification({
    required this.category,
    required this.label,
    required this.confidence,
    this.isDnd = false,
  });

  @override
  String toString() => '$category / $label (${(confidence * 100).toInt()}%)';
}

class ClassificationRule {
  final String processPattern;
  final String? titlePattern;
  final String category;
  final String label;
  final bool isDnd;

  const ClassificationRule({
    required this.processPattern,
    this.titlePattern,
    required this.category,
    required this.label,
    this.isDnd = false,
  });
}

class ActivityClassifier {
  static final List<ClassificationRule> _defaultRules = <ClassificationRule>[
    const ClassificationRule(
      processPattern: 'code.exe',
      category: '\u7f16\u7a0b',
      label: 'VS Code',
    ),
    const ClassificationRule(
      processPattern: 'devenv.exe',
      category: '\u7f16\u7a0b',
      label: 'Visual Studio',
    ),
    const ClassificationRule(
      processPattern: 'idea64.exe',
      category: '\u7f16\u7a0b',
      label: 'IntelliJ IDEA',
    ),
    const ClassificationRule(
      processPattern: 'pycharm64.exe',
      category: '\u7f16\u7a0b',
      label: 'PyCharm',
    ),
    const ClassificationRule(
      processPattern: 'webstorm64.exe',
      category: '\u7f16\u7a0b',
      label: 'WebStorm',
    ),
    const ClassificationRule(
      processPattern: 'cursor.exe',
      category: '\u7f16\u7a0b',
      label: 'Cursor',
    ),
    const ClassificationRule(
      processPattern: 'windowsterminal.exe',
      category: '\u7f16\u7a0b',
      label: '\u7ec8\u7aef',
    ),
    const ClassificationRule(
      processPattern: 'powershell.exe',
      category: '\u7f16\u7a0b',
      label: 'PowerShell',
    ),
    const ClassificationRule(
      processPattern: 'cmd.exe',
      category: '\u7f16\u7a0b',
      label: '\u547d\u4ee4\u63d0\u793a\u7b26',
    ),
    const ClassificationRule(
      processPattern: 'git',
      category: '\u7f16\u7a0b',
      label: 'Git',
    ),
    const ClassificationRule(
      processPattern: 'chrome.exe',
      category: '\u6d4f\u89c8\u7f51\u9875',
      label: 'Chrome',
    ),
    const ClassificationRule(
      processPattern: 'msedge.exe',
      category: '\u6d4f\u89c8\u7f51\u9875',
      label: 'Edge',
    ),
    const ClassificationRule(
      processPattern: 'firefox.exe',
      category: '\u6d4f\u89c8\u7f51\u9875',
      label: 'Firefox',
    ),
    const ClassificationRule(
      processPattern: 'opera.exe',
      category: '\u6d4f\u89c8\u7f51\u9875',
      label: 'Opera',
    ),
    const ClassificationRule(
      processPattern: 'brave.exe',
      category: '\u6d4f\u89c8\u7f51\u9875',
      label: 'Brave',
    ),
    const ClassificationRule(
      processPattern: 'winword.exe',
      category: '\u529e\u516c',
      label: 'Word',
    ),
    const ClassificationRule(
      processPattern: 'excel.exe',
      category: '\u529e\u516c',
      label: 'Excel',
    ),
    const ClassificationRule(
      processPattern: 'powerpnt.exe',
      category: '\u529e\u516c',
      label: 'PowerPoint',
    ),
    const ClassificationRule(
      processPattern: 'onenote.exe',
      category: '\u529e\u516c',
      label: 'OneNote',
    ),
    const ClassificationRule(
      processPattern: 'outlook.exe',
      category: '\u529e\u516c',
      label: 'Outlook',
    ),
    const ClassificationRule(
      processPattern: 'teams.exe',
      category: '\u6c9f\u901a',
      label: 'Teams',
    ),
    const ClassificationRule(
      processPattern: 'notion.exe',
      category: '\u529e\u516c',
      label: 'Notion',
    ),
    const ClassificationRule(
      processPattern: 'obsidian.exe',
      category: '\u529e\u516c',
      label: 'Obsidian',
    ),
    const ClassificationRule(
      processPattern: 'wechat.exe',
      category: '\u6c9f\u901a',
      label: '\u5fae\u4fe1',
    ),
    const ClassificationRule(
      processPattern: 'qq.exe',
      category: '\u6c9f\u901a',
      label: 'QQ',
    ),
    const ClassificationRule(
      processPattern: 'dingtalk.exe',
      category: '\u6c9f\u901a',
      label: '\u9489\u9489',
    ),
    const ClassificationRule(
      processPattern: 'telegram.exe',
      category: '\u6c9f\u901a',
      label: 'Telegram',
    ),
    const ClassificationRule(
      processPattern: 'discord.exe',
      category: '\u6c9f\u901a',
      label: 'Discord',
    ),
    const ClassificationRule(
      processPattern: 'slack.exe',
      category: '\u6c9f\u901a',
      label: 'Slack',
    ),
    const ClassificationRule(
      processPattern: 'spotify.exe',
      category: '\u5a31\u4e50',
      label: 'Spotify',
    ),
    const ClassificationRule(
      processPattern: 'cloudmusic.exe',
      category: '\u5a31\u4e50',
      label: '\u7f51\u6613\u4e91\u97f3\u4e50',
    ),
    const ClassificationRule(
      processPattern: 'potplayer',
      category: '\u5a31\u4e50',
      label: 'PotPlayer',
    ),
    const ClassificationRule(
      processPattern: 'vlc.exe',
      category: '\u5a31\u4e50',
      label: 'VLC',
    ),
    const ClassificationRule(
      processPattern: 'bilibili',
      category: '\u5a31\u4e50',
      label: '\u54d4\u54e9\u54d4\u54e9',
    ),
    const ClassificationRule(
      processPattern: 'valorant',
      category: '\u6e38\u620f',
      label: '\u65e0\u754f\u5951\u7ea6',
      isDnd: true,
    ),
    const ClassificationRule(
      processPattern: 'leagueclient',
      category: '\u6e38\u620f',
      label: '\u82f1\u96c4\u8054\u76df',
      isDnd: true,
    ),
    const ClassificationRule(
      processPattern: 'steam.exe',
      category: '\u6e38\u620f',
      label: 'Steam',
    ),
    const ClassificationRule(
      processPattern: 'epicgameslauncher',
      category: '\u6e38\u620f',
      label: 'Epic Games',
    ),
    const ClassificationRule(
      processPattern: 'genshinimpact',
      category: '\u6e38\u620f',
      label: '\u539f\u795e',
      isDnd: true,
    ),
    const ClassificationRule(
      processPattern: 'figma',
      category: '\u8bbe\u8ba1',
      label: 'Figma',
    ),
    const ClassificationRule(
      processPattern: 'photoshop',
      category: '\u8bbe\u8ba1',
      label: 'Photoshop',
    ),
    const ClassificationRule(
      processPattern: 'explorer.exe',
      category: '\u7cfb\u7edf',
      label: '\u6587\u4ef6\u8d44\u6e90\u7ba1\u7406\u5668',
    ),
    const ClassificationRule(
      processPattern: 'flowplan.exe',
      category: '\u7cfb\u7edf\u5de5\u5177',
      label: 'FlowPlan',
    ),
    const ClassificationRule(
      processPattern: 'calllclaude.exe',
      category: '\u7cfb\u7edf\u5de5\u5177',
      label: 'FlowPlan',
    ),
  ];

  List<ClassificationRule> _userRules = <ClassificationRule>[];

  void setUserRules(List<ClassificationRule> rules) {
    _userRules = rules;
  }

  ActivityClassification classify(WindowSnapshot snapshot) {
    final processLower = snapshot.processName.toLowerCase();
    final titleLower = snapshot.windowTitle.toLowerCase();

    for (final rule in _userRules) {
      if (_matches(processLower, titleLower, rule)) {
        return ActivityClassification(
          category: rule.category,
          label: rule.label,
          confidence: 1,
          isDnd: rule.isDnd || snapshot.isFullscreen,
        );
      }
    }

    for (final rule in _defaultRules) {
      if (_matches(processLower, titleLower, rule)) {
        return ActivityClassification(
          category: rule.category,
          label: rule.label,
          confidence: 0.9,
          isDnd: rule.isDnd || snapshot.isFullscreen,
        );
      }
    }

    if (snapshot.isFullscreen) {
      return ActivityClassification(
        category: '\u6e38\u620f',
        label: snapshot.processName,
        confidence: 0.5,
        isDnd: true,
      );
    }

    return ActivityClassification(
      category: '\u672a\u5206\u7c7b',
      label: snapshot.processName,
      confidence: 0,
    );
  }

  ActivityClassification classifyAndroidApp({
    required String packageName,
    String? appLabel,
    String? className,
    DateTime? timestamp,
  }) {
    final snapshot = WindowSnapshot(
      processName: packageName,
      className: className ?? '',
      windowTitle: (appLabel?.trim().isNotEmpty == true)
          ? appLabel!.trim()
          : packageName,
      isFullscreen: false,
      timestamp: timestamp ?? DateTime.now(),
    );

    final classification = classify(snapshot);
    if (classification.confidence > 0) {
      return classification;
    }

    final displayLabel = appLabel?.trim();
    if (displayLabel != null && displayLabel.isNotEmpty) {
      return ActivityClassification(
        category: classification.category,
        label: displayLabel,
        confidence: classification.confidence,
        isDnd: classification.isDnd,
      );
    }

    return classification;
  }

  bool _matches(
    String processLower,
    String titleLower,
    ClassificationRule rule,
  ) {
    final processMatch =
        processLower.contains(rule.processPattern.toLowerCase());
    if (!processMatch) {
      return false;
    }
    if (rule.titlePattern != null) {
      return titleLower.contains(rule.titlePattern!.toLowerCase());
    }
    return true;
  }
}
