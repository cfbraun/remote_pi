# Convenience targets around run.sh — reproducible Cockpit build/test in Docker.
#
#   make -C cockpit/docker image     # build the toolchain image
#   make -C cockpit/docker analyze   # flutter analyze
#   make -C cockpit/docker test      # flutter test
#   make -C cockpit/docker check     # analyze + test
#   make -C cockpit/docker shell     # interactive shell in the image
.PHONY: image analyze test check shell

image:
	docker build -t remote-pi-cockpit-build:flutter3.47.5-zig0.16.0 .

analyze:
	./run.sh flutter analyze

test:
	./run.sh flutter test

check:
	./run.sh "flutter pub get && flutter analyze && flutter test"

shell:
	./run.sh bash
