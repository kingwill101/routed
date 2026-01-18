FROM golang:1.22 AS build

WORKDIR /app
COPY benchmarks/servers/go/go.mod ./
COPY benchmarks/servers/go/main.go ./

RUN go build -o /app/server .

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/server /app/server

ENV PORT=8004
EXPOSE 8004

CMD ["/app/server"]
