// 브라우저 파일 내려받기.
//
// package:web 은 웹 전용이라 안드로이드 빌드에서 깨진다.
// 조건부 import 로 플랫폼별 구현을 고른다.
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
