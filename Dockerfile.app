FROM nginx:alpine
COPY app/build/web/ /usr/share/nginx/html/
CMD sh -c "printf 'server{listen %s;root /usr/share/nginx/html;index index.html;location/{try_files \$uri \$uri/ /index.html;}}' \"${PORT:-80}\" > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
