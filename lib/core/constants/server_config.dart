/// 后端服务器地址（阿里云 Windows Server + Tomcat）。
///
/// 换 IP / 换域名时只改这一处，然后重新发一次 APK。
/// 也可以在构建时用 --dart-define=SERVER_BASE_URL=http://x.x.x.x:8080 覆盖。
const String serverBaseUrl = String.fromEnvironment(
  'SERVER_BASE_URL',
  defaultValue: 'http://121.199.75.235:8080',
);

/// 轮协（值班协作）接口根地址。
const String scheduleApiBaseUrl = '$serverBaseUrl/schedule';
