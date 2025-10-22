FROM dart:3.9-sdk AS build
WORKDIR /app
COPY . .
RUN dart pub get

FROM dart:3.9
WORKDIR /app/examples/oauth_keycloak
COPY --from=build /app /app
EXPOSE 8080
CMD ["dart", "run", "examples/oauth_keycloak/bin/server.dart"]
