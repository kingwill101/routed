import 'package:routed_node/bun.dart';
import 'package:routed_node/cloudflare.dart';
import 'package:routed_node/deno.dart';
import 'package:routed_node/netlify.dart';
import 'package:routed_node/node.dart';
import 'package:routed_node/vercel.dart';

void main() {
  print([
    serveNode,
    serveBun,
    serveDeno,
    defineCloudflareFetch,
    defineVercelFetch,
    defineNetlifyFetch,
  ]);
}
