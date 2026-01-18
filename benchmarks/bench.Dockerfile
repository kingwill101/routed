FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends wrk ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /bench
COPY benchmarks/scripts/bench.sh /bench/bench.sh

ENTRYPOINT ["/bench/bench.sh"]
