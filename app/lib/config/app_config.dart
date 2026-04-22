class AppConfig {
  // 안드로이드 에뮬레이터에서 로컬 PC 서버 접속 시 10.0.2.2 사용
  // 실제 안드로이드 폰으로 테스트하면 PC의 실제 IP로 바꿔야 함
  // iOS 시뮬레이터는 보통 127.0.0.1 또는 localhost 사용 가능
  static const String baseUrl = 'http://10.0.2.2:8000';
}