#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

SIM_ID="${SIM_ID:-9999}"
BALL_SPEED="${BALL_SPEED:-171}"
LAUNCH_ANGLE="${LAUNCH_ANGLE:-10}"
BACKSPIN="${BACKSPIN:-2545}"
SIDESPIN="${SIDESPIN:-10}"
TARGET_DIST="${TARGET_DIST:-282}"
TARGET_RADIUS="${TARGET_RADIUS:-15}"

make

./golf_sim "${SIM_ID}" "${BALL_SPEED}" "${LAUNCH_ANGLE}" "${BACKSPIN}" "${SIDESPIN}" "${TARGET_DIST}" "${TARGET_RADIUS}"

python3 plot_dispersion.py --sim-id "${SIM_ID}"
