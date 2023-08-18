.PHONY: all scanner bcprinter httpd artemis

all: scanner bcprinter httpd artemis

scanner:
	docker build -t catweazle/scanner:latest -t catweazle/scanner:0.1.3 ./scanner

bcprinter:
	docker build -t catweazle/bcprinter:latest -t catweazle/bcprinter:0.0.1 ./bcprinter
	
httpd:
	docker build -t catweazle/httpd:latest ./httpd

artemis:
	docker build -t catweazle/artemis:latest ./artemis

node-red:
	docker build -t catweazle/node-red:latest ./node-red
