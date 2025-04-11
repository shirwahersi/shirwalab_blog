.PHONY: clean
clean:
	rm -rf public/*

.PHONY: build
build:
	hugo

.PHONY: install
install:
	git clone https://github.com/jpanther/congo.git themes/congo

.PHONY: serve
serve:
	hugo server --buildDrafts --disableFastRender --gc --ignoreCache --noHTTPCache --forceSyncStatic --verbose -w 


.PHONY: deploy
deploy: clean build
	cd public && aws s3 sync . s3://shirwalab-blog --profile shirwalab
	aws cloudfront create-invalidation --distribution-id E22L5ZR0MWEVHP --paths "/*" --profile shirwalab > /dev/null