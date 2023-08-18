FROM catweazle/perl:latest

MAINTAINER Alexander Thiel (alex@alx-development.de)

# Copy the source into the image
ADD ./src/scanner.pl /usr/src/scanner.pl

# Make the default data directory
RUN mkdir -p /var/scanner/data
WORKDIR /var/scanner

# Running the daemon
CMD [ "perl", "/usr/src/scanner.pl" ]
