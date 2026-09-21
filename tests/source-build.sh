#!/usr/bin/env bash
# Run only inside a disposable Ubuntu container: prepare, build, and exercise ROS 2.
set -euo pipefail
[[ ${SOURCE_BUILD_TEST_CONTAINER:-} == 1 ]] || { echo 'Run this test in a disposable container with SOURCE_BUILD_TEST_CONTAINER=1.' >&2; exit 1; }
directory=$(cd -- "$(dirname -- "$0")" && pwd)
setup_script=${1:-$directory/../setup-source.sh}
cp "$setup_script" /tmp/source-setup-under-test.sh
setup_script=/tmp/source-setup-under-test.sh
apt-get -o APT::Update::Error-Mode=any update
apt-get install -y --no-install-recommends sudo ca-certificates
if ! id builder >/dev/null 2>&1; then useradd --create-home --shell /bin/bash builder; fi
printf 'builder ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/source-build-test
chmod 440 /etc/sudoers.d/source-build-test
# Exercise both user entry points; the second run must reuse system configuration.
runuser -u builder -- sh "$setup_script" --yes
runuser -u builder -- sudo sh "$setup_script" --yes
[[ $(stat -c %U /home/builder/.ros/rosdep/sources.cache) == builder ]]
# shellcheck disable=SC1091
source /etc/os-release
case "$VERSION_ID" in
    22.04) distro=humble; skip='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
    24.04) distro=jazzy; skip='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
    26.04) distro=lyrical; skip='fastcdr rti-connext-dds-7.7.0 urdfdom_headers' ;;
    *) exit 1 ;;
esac
runuser -u builder -- env DISTRO="$distro" SKIP_KEYS="$skip" bash <<'BUILD'
set -euo pipefail
cd "$HOME"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
[[ $(locale charmap) == UTF-8 ]]
mkdir -p "ros2_$DISTRO/src"
cd "ros2_$DISTRO"
curl -fL --proto '=https' --proto-redir '=https' "https://raw.githubusercontent.com/ros2/ros2/$DISTRO/ros2.repos" -o ros2.repos
vcs import --recursive --input ros2.repos src
vcs export --exact src > exact.repos
rosdep install --from-paths src --ignore-src --rosdistro "$DISTRO" -y --skip-keys "$SKIP_KEYS"
# Build the C++ and Python demos, CLI, and their complete dependency closure from source.
# Limiting concurrency keeps peak memory manageable on standard CI runners.
export MAKEFLAGS=-j2 CMAKE_BUILD_PARALLEL_LEVEL=2
colcon build --symlink-install --executor sequential \
    --packages-up-to demo_nodes_cpp demo_nodes_py ros2run \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
set +u
source install/local_setup.bash
set -u
export ROS_DOMAIN_ID=83
ros2 run demo_nodes_cpp talker > talker.log 2>&1 &
talker=$!
ros2 run demo_nodes_py listener > listener.log 2>&1 &
listener=$!
trap 'kill "$talker" "$listener" 2>/dev/null || true; wait "$talker" "$listener" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<60; attempt++)); do
    if grep -q 'I heard:' listener.log && grep -q 'Publishing:' talker.log; then
        echo 'Source-built C++ talker and Python listener communicated successfully.'
        exit 0
    fi
    kill -0 "$talker" "$listener" || { cat talker.log listener.log >&2; exit 1; }
    sleep 1
done
cat talker.log listener.log >&2
echo 'Timed out waiting for source-built nodes to communicate.' >&2
exit 1
BUILD
