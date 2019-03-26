#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
export CROMWELL_BUILD_REQUIRES_SECURE=true
# import in shellcheck / CI / IntelliJ compatible ways
# shellcheck source=/dev/null
source "${BASH_SOURCE%/*}/test.inc.sh" || source test.inc.sh

# BEGIN docker compose deadlock Frankenstein
# This does *not* actually run docker-compose! That will be done by Centaur with changes to support Docker composing.
# Much of this is derived from the deadlock-disproving `testDockerDeadlock.sh` but removes both the deadlock-generating
# script *and* MySQL. The former is removed for obvious reasons, the latter is removed because this docker-compose'd
# cluster is going to be restarted by Centaur but there's no reason MySQL should be restarted at the same time.

set -o errexit -o nounset -o pipefail

cromwell::build::setup_common_environment

# BEGIN Centaur stuff
GOOGLE_AUTH_MODE="service-account"
GOOGLE_REFRESH_TOKEN_PATH="${CROMWELL_BUILD_RESOURCES_DIRECTORY}/papi_refresh_token.txt"

# Export variables used in conf files
export GOOGLE_AUTH_MODE
export GOOGLE_REFRESH_TOKEN_PATH

# Copy rendered files
mkdir -p "${CROMWELL_BUILD_CENTAUR_TEST_RENDERED}"
cp \
    "${CROMWELL_BUILD_RESOURCES_DIRECTORY}/private_docker_papi_v2_usa.options" \
    "${CROMWELL_BUILD_CENTAUR_TEST_RENDERED}"

# END Centaur stuff

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
