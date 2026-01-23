.PHONY: init
init:
	@test -f go.mod || hugo mod init github.com/shirwahersi/shirwalab-blog
	hugo mod get

.PHONY: update
update:
	hugo mod get -u
	hugo mod tidy

.PHONY: clean
clean:
	rm -rf public/*
	hugo mod clean

.PHONY: build
build:
	hugo --minify

.PHONY: serve
serve:
	hugo server --buildDrafts --disableFastRender

.PHONY: deploy
deploy: clean build
	cd public && aws s3 sync . s3://shirwalab-blog --profile shirwalab
	aws cloudfront create-invalidation --distribution-id E22L5ZR0MWEVHP --paths "/*" --profile shirwalab > /dev/null
