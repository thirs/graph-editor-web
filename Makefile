all:
	elm make src/Main.elm --output=elm.js
	yarn compile
	yarn make
install:
	dpkg -i out/make/deb/x64/coreact-yade_*_amd64.deb
make-test:
	elm make src/Main.elm --output=elm.js
	yarn compile
start:
	python3 -m webbrowser -n -t "http://localhost:8000/index.html"
elm:
	elm make src/Main.elm --output=elm.js
