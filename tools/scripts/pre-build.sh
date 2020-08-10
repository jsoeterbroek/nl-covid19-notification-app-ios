#!/usr/bin/env bash

env

if [ -z "$NETWORK_CONFIGURATION" ]
then
      NETWORK_CONFIGURATION="Test"
fi

if [ -z "$LOG_LEVEL" ]
then
      LOG_LEVEL="debug"
fi

if [ -z "$BUILD_ID" ]
then
      BUILD_ID="1"
fi

if [ -z "$BUNDLE_IDENTIFIER" ]
then 
      BUNDLE_IDENTIFIER="nl.rijksoverheid.en.test"
fi

if [ -z "$BUNDLE_DISPLAY_NAME" ]
then
      BUNDLE_DISPLAY_NAME="CoronaMelder 🐞"
fi

if [ -z "$RELEASE_PROVISIONING_PROFILE" ]
then
      RELEASE_PROVISIONING_PROFILE="EN Tracing development"
fi

if [ -z "$SHARE_LOGS_ENABLED" ]
then
      SHARE_LOGS_ENABLED="false"
fi

brew install yq
yq w -i project.yml "targets.EN.info.properties.SHARE_LOGS_ENABLED" ${SHARE_LOGS_ENABLED}
yq w -i project.yml "targets.EN.info.properties.NETWORK_CONFIGURATION" ${NETWORK_CONFIGURATION}
yq w -i project.yml "targets.EN.info.properties.LOG_LEVEL" ${LOG_LEVEL}
yq w -i project.yml --tag '!!str' "targets.EN.info.properties.CFBundleDisplayName" "${BUNDLE_DISPLAY_NAME}"
yq w -i project.yml --tag '!!str' "targets.EN.info.properties.CFBundleVersion" ${BUILD_ID}
yq w -i project.yml "targets.EN.settings.base.PRODUCT_BUNDLE_IDENTIFIER" ${BUNDLE_IDENTIFIER}
yq w -i project.yml "targets.EN.settings.configs.Release.PROVISIONING_PROFILE_SPECIFIER" "${RELEASE_PROVISIONING_PROFILE}"
yq w -i project.yml --tag '!!str' "targets.EN.info.properties.GitHash" $(git rev-parse --short=7 HEAD)

if [ ! -z "$USE_DEVELOPER_MENU" ]
then
	yq w -i project.yml -- "targets.ENCore.settings.base.OTHER_SWIFT_FLAGS" -DUSE_DEVELOPER_MENU
else 
      yq d -i project.yml -- "targets.ENCore.settings.base.OTHER_SWIFT_FLAGS"
fi

cat project.yml

make install_ci_deps && make generate_project