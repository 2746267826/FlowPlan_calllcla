class OutlookOAuthPlatformConfig {
  const OutlookOAuthPlatformConfig._();

  static const authority = 'https://login.microsoftonline.com/consumers';
  static const authorizeEndpoint = '$authority/oauth2/v2.0/authorize';
  static const tokenEndpoint = '$authority/oauth2/v2.0/token';
  static const defaultClientId = '';
  static const redirectUri =
      'https://login.microsoftonline.com/common/oauth2/nativeclient';
  static const graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const preferTimezone = 'Asia/Tokyo';
  static const scopes = <String>[
    'openid',
    'profile',
    'offline_access',
    'User.Read',
    'Calendars.ReadWrite',
  ];

  static String get scopeString => scopes.join(' ');
}
