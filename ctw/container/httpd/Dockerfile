FROM httpd:latest
MAINTAINER Alexander Thiel (alex@alx-development.de)

# Generating the default folder structure
RUN mkdir -p /usr/local/apache2/webdav

# Copy the default webspace configuration into the image
ADD ./src/httpd.conf 	/usr/local/apache2/conf/httpd.conf
