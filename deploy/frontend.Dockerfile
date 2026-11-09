FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app
COPY OpenM_frontend_flutter/pubspec.* ./
RUN flutter pub get
COPY OpenM_frontend_flutter/lib ./lib
COPY OpenM_frontend_flutter/web ./web
RUN flutter build web --release --no-pub --dart-define=API_BASE_URL=/api

FROM nginx:1.27-alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
