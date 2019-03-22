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

if [[ "${CROMWELL_BUILD_PROVIDER}" == "${CROMWELL_BUILD_PROVIDER_TRAVIS}" ]]; then
  # Upgrade docker-compose so that we get the correct exit codes
  docker-compose -version
  sudo rm /usr/local/bin/docker-compose
  curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" > docker-compose
  chmod +x docker-compose
  sudo mv docker-compose /usr/local/bin
  docker-compose -version
fi

export TEST_CROMWELL_TAG=just-testing-horicromtal

docker image ls -q broadinstitute/cromwell:"${TEST_CROMWELL_TAG}" | grep . || \
CROMWELL_SBT_DOCKER_TAGS="${TEST_CROMWELL_TAG}" sbt server/docker

#echo "ip addr show"
#ip addr show || true


#echo "Local IP command: ip addr show docker0 | grep 'inet ' | awk '{print \$2}' | cut -f1 -d'/'"
#ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/' || true

#export TEST_HOST_IP=$(ip addr show docker0 | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/' || ipconfig getifaddr en0)

# MYSQL_HOST_IP="${TEST_HOST_IP}" \
CROMWELL_TAG="${TEST_CROMWELL_TAG}" \
docker-compose -f scripts/docker-compose-mysql/docker-compose-horicromtal.yml up -d
#docker-compose -f scripts/docker-compose-mysql/docker-compose-horicromtal.yml up --scale cromwell_soldier=2 -d

# what the
# Error: No such network: docker-compose-mysql_default
#echo "docker network inspect docker-compose-mysql_default"
#docker network inspect docker-compose-mysql_default

# Give them some time to be ready
sleep 30

# Call centaur with our custom test case
CENTAUR_TEST_FILE=scripts/docker-compose-mysql/test/hello.test \
sbt "centaur/it:testOnly *ExternalTestCaseSpec"

# Tear everything down
# MYSQL_HOST_IP="${TEST_HOST_IP}" \
CROMWELL_TAG="${TEST_CROMWELL_TAG}" \
docker-compose -f scripts/docker-compose-mysql/docker-compose-horicromtal.yml down
