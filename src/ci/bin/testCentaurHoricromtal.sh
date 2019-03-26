#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
export CROMWELL_BUILD_REQUIRES_SECURE=true
# import in shellcheck / CI / IntelliJ compatible ways
# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/test.inc.sh" || source test.inc.sh

cromwell::build::setup_common_environment

cromwell::build::setup_centaur_environment

export TEST_CROMWELL_TAG=just-testing-horicromtal

docker image ls -q broadinstitute/cromwell:"${TEST_CROMWELL_TAG}" | grep . || \
CROMWELL_SBT_DOCKER_TAGS="${TEST_CROMWELL_TAG}" sbt server/docker

# FIXME make a nice directory like the above for Centaur and maybe copy just the stuff we care about
# FIXME assuming that doesn't turn out to be a huge PITA.
cp scripts/docker-compose-mysql/compose/cromwell/app-config/* target/ci/resources

CROMWELL_TAG="${TEST_CROMWELL_TAG}" \
docker-compose -f scripts/docker-compose-mysql/docker-compose-horicromtal.yml up -d

# Give them some time to be ready
sleep 30

# Call centaur with our custom test case
CENTAUR_TEST_FILE=scripts/docker-compose-mysql/test/hello_yes_docker.test \
sbt "centaur/it:testOnly *ExternalTestCaseSpec"

# Tear everything down
CROMWELL_TAG="${TEST_CROMWELL_TAG}" \
docker-compose -f scripts/docker-compose-mysql/docker-compose-horicromtal.yml down
