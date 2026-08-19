import { createServer } from "node:http";

createServer((_request, response) => {
  response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
  response.end("container-fetch-ok");
}).listen(8080, "0.0.0.0");
