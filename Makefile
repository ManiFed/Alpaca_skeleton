IOS_SCHEME      := BoundlessSkies
IOS_DESTINATION := platform=iOS Simulator,name=iPhone 16

# Build the native SwiftUI iOS app.
.PHONY: build-ios
build-ios:
	cd app && xcodebuild -scheme $(IOS_SCHEME) \
		-destination '$(IOS_DESTINATION)' \
		build

.PHONY: test-ios
test-ios:
	cd app && xcodebuild -scheme $(IOS_SCHEME) \
		-destination '$(IOS_DESTINATION)' \
		test

# Deploy the cloud server to Railway
.PHONY: deploy-cloud
deploy-cloud:
	railway up --detach

# Deploy server-side services. The iOS app ships through Xcode/App Store tooling.
.PHONY: deploy
deploy: deploy-cloud
