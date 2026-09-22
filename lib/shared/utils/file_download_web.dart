import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 브라우저에서 바이트를 파일로 내려받는다.
///
/// Blob URL 을 만들어 보이지 않는 <a download> 를 클릭시키는 방식이다.
/// 사용이 끝난 URL 은 바로 해제해 메모리를 잡아두지 않게 한다.
void downloadBytes(List<int> bytes, String fileName) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    <JSAny>[data.toJS].toJS,
    web.BlobPropertyBag(
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  );

  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
