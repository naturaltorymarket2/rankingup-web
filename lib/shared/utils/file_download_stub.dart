/// 웹이 아닌 플랫폼에서는 파일 내려받기를 쓰지 않는다.
/// (대량 등록은 광고주 웹 전용 기능이다)
void downloadBytes(List<int> bytes, String fileName) {
  throw UnsupportedError('파일 내려받기는 웹에서만 지원합니다.');
}
