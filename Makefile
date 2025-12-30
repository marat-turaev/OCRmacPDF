APP_NAME=ocrmacpdf
CC=clang
SRC=main.m

all: build

check:
	@/usr/bin/xcode-select -p >/dev/null 2>&1 || (echo "Xcode Command Line Tools not found. Run: xcode-select --install" && exit 1)
	@/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ if ($$1 < 13) { print "macOS 13+ required. Current: " $$0; exit 1 } }'

build: check
	$(CC) -fobjc-arc -framework Foundation -framework PDFKit $(SRC) -o $(APP_NAME)

run: build
	./$(APP_NAME)

clean:
	rm -f $(APP_NAME)
