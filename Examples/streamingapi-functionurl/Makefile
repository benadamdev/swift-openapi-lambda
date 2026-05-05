### Add functions here and link them to builder-bot format MUST BE "build-FunctionResourceName in template.yaml"

build-StreamingNumbers: builder-bot

# Helper commands
build:
	sam build

deploy:
	sam deploy --guided

logs:
	sam logs --stack-name StreamingNumbers

tail:
	sam logs --stack-name StreamingNumbers --tail

local:
	swift run StreamingNumbers

# Replace with the FunctionUrl emitted by `sam deploy` (or read from the stack outputs).
# `--no-buffer` is critical: without it curl buffers the entire body and you don't see streaming.
invoke:
##	curl -v --no-buffer -X POST -H 'Content-Type: application/json' \
##	     --data '{"count": 10}' \
##	     https://<FUNCTION_URL_ID>.lambda-url.<REGION>.on.aws/numbers/stream
	@echo "Update the URL in this Makefile to your deployed Function URL, then run:"
	@echo "  make invoke"

######################  No Change required below this line  ##########################

builder-bot:
	$(eval $@PRODUCT = $(subst build-,,$(MAKECMDGOALS)))
	$(eval $@BUILD_DIR = $(PWD)/.aws-sam/build-swift)
	$(eval $@STAGE = $($@BUILD_DIR)/lambda)
	$(eval $@ARTIFACTS_DIR = $(PWD)/.aws-sam/build/$($@PRODUCT))

## Building from swift-openapi-lambda in a local directory (not from Github)
##  2. Change `Package.swift` dependency to path: "../.."

##  3. add /../.. to BUILD_SRC
	$(eval $@BUILD_SRC = $(PWD)/../..)
## 	$(eval $@BUILD_SRC = $(PWD))

##  4. add `cd Examples/streamingapi-functionurl &&` to the docker BUILD_CMD
	$(eval $@BUILD_CMD = "cd Examples/streamingapi-functionurl && swift build --static-swift-stdlib --product $($@PRODUCT) -c release --build-path /build-target")
## 	$(eval $@BUILD_CMD = "swift build --static-swift-stdlib --product $($@PRODUCT) -c release --build-path /build-target")

	# build docker image to compile Swift for Linux
	docker build -f Dockerfile . -t swift-builder

	# prep directories
	rm -rf $($@ARTIFACTS_DIR)
	mkdir -p $($@BUILD_DIR)/lambda $($@ARTIFACTS_DIR)

	# compile application inside Docker image using source code from local project folder
	docker run --rm -v $($@BUILD_DIR):/build-target -v $($@BUILD_SRC):/build-src -w /build-src swift-builder bash -cl $($@BUILD_CMD)

	# create lambda bootstrap file
	docker run --rm -v $($@BUILD_DIR):/build-target -v `pwd`:/build-src -w /build-src swift-builder bash -cl "cd /build-target/lambda && ln -s $($@PRODUCT) /bootstrap"

	# copy binary to artifacts dir
	cp $($@BUILD_DIR)/release/$($@PRODUCT) $($@ARTIFACTS_DIR)/bootstrap

	# copy resources to artifacts dir
	[ -d "$($@BUILD_DIR)/release/$($@PRODUCT)_$($@PRODUCT).resources" ] && cp $($@BUILD_DIR)/release/$($@PRODUCT)_$($@PRODUCT).resources/* $($@ARTIFACTS_DIR) || true
