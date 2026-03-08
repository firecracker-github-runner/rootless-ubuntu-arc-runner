#!/bin/env bash

set -eoux pipefail

cp -r /home/runner_base/* /home/runner_base/.* /home/runner
cd /home/runner
./run.sh
