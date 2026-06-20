BINARY_NAME=hacker-dash
GO_BIN=/usr/local/bin

all: build

build:
	go build -o $(BINARY_NAME) main.go

install: build
	sudo mv $(BINARY_NAME) $(GO_BIN)/
	chmod +x hacker-dash.sh

clean:
	rm -f $(BINARY_NAME)

test:
	go test ./...

.PHONY: all build install clean test
