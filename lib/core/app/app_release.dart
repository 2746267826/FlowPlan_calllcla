/// Release metadata entry point.
/// Keep this file in sync with pubspec.yaml, Runner.rc, and version.txt.
const appProductName = 'FlowPlan';
const appTagline = '\u4e2d\u6587\u4f18\u5148\u7684\u672c\u5730\u667a\u80fd\u89c4\u5212\u5de5\u5177';
const appMarketingVersion = '1.3.1';
const appBuildNumber = '131';
const appMsixVersion = '1.3.1.131';

String get appDisplayVersion => 'v$appMarketingVersion';

String get appPackageVersion => '$appMarketingVersion+$appBuildNumber';

String get appAboutSubtitle => '$appDisplayVersion \u00b7 $appTagline';
