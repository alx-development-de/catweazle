FROM catweazle/perl:latest

MAINTAINER Alexander Thiel (alex@alx-development.de)

# Copy the source into the image
ADD ./src/bcprinter.pl /usr/src/bcprinter.pl
ADD ./src/template.lbl /usr/src/template.lbl

# Running the daemon
CMD [ "perl", "/usr/src/bcprinter.pl" ]
