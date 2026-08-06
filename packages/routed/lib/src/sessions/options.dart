import 'package:server_sessions/src/options.dart' as ss;

class Options extends ss.SessionOptions {
  Options({
    super.path,
    super.domain,
    super.maxAge,
    super.secure,
    super.httpOnly,
    super.sameSite,
    super.partitioned,
  });
}
