FROM nginx:latest
MAINTAINER Alexander Thiel (alex@alx-development.de)

# Setup nginx
COPY src/nginx.conf /etc/nginx/templates/default.conf.template

RUN rm /etc/nginx/conf.d/default.conf

# Copy static content
COPY src/html/ /etc/nginx/html/

EXPOSE 80