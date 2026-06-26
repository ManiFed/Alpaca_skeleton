FROM nginx:alpine
COPY app/build/web/ /usr/share/nginx/html/
