class OutlookOAuthPlatformConfig {
  const OutlookOAuthPlatformConfig._();

  static const authority = '';
  static const authorizeEndpoint = '';
  static const tokenEndpoint = '';
  static const defaultClientId = '';
  static const redirectUri = '';
  static const graphBaseUrl = '';
  static const preferTimezone = 'Asia/Shanghai';
  static const scopes = <String>[
    'Calendars.Read',
  ];

  static String get scopeString => scopes.join(' ');
}
