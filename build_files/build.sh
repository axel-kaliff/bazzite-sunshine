#!/bin/bash

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

copr=lizardbyte/stable
timeout 120 dnf5 -y copr enable "$copr"
# Repository errors must fail instead of looking like an absent package.
packages=$(timeout 300 dnf5 --refresh --repo='copr:copr.fedorainfracloud.org:lizardbyte:stable' \
    --setopt='*.skip_if_unavailable=False' repoquery --available --queryformat '%{name}\n' Sunshine)
if ! grep -qx Sunshine <<< "$packages"; then
    timeout 120 dnf5 -y copr disable "$copr"
    copr=lizardbyte/beta
    timeout 120 dnf5 -y copr enable "$copr"
fi
echo "Installing Sunshine from $copr"
timeout 600 dnf5 -y install Sunshine
timeout 120 dnf5 -y copr disable "$copr"

getcap "$(readlink -f /usr/bin/sunshine)" | grep -w cap_sys_admin
timeout 30 systemctl --global enable app-dev.lizardbyte.app.Sunshine.service \
    sunshine-stream-watchdog.service sunshine-health.timer
