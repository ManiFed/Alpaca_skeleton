FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src
COPY app/pubspec.yaml app/pubspec.lock* ./app/
WORKDIR /src/app
RUN flutter pub get
WORKDIR /src
COPY app ./app
WORKDIR /src/app
RUN flutter build web --release \
    --base-href=/ \
    --dart-define=API_BASE=https://api.thetelescope.net

FROM nginx:alpine
COPY --from=build /src/app/build/web/ /usr/share/nginx/html/
COPY nginx.app.conf /etc/nginx/conf.d/default.conf
CMD sh -c "sed -i \"s/PORT_PLACEHOLDER/${PORT:-80}/\" /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
