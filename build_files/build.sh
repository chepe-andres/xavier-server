#!/usr/bin/env bash

set -xeuo pipefail

dnf update -y
dnf install -y epel-release

dnf install -y "https://zfsonlinux.org/epel/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm"
dnf install -y kernel-devel
dnf install -y zfs

KERNEL_VERSION="$(find "/usr/lib/modules" -maxdepth 1 -type d ! -path "/usr/lib/modules" -exec basename '{}' ';' | sort | grep -v kabi | tail -n 1)"
ZFS_VERSION="$(find /usr/src -maxdepth 1 -iname "zfs*" -exec basename '{}' ';' | cut -f2 -d-)"

dkms install -m zfs -v "${ZFS_VERSION}" -k "${KERNEL_VERSION}"
cat /var/lib/dkms/*/*/build/make.log || :

dnf config-manager --add-repo "https://negativo17.org/repos/epel-nvidia-580.repo"
dnf config-manager --set-disabled "epel-nvidia-580"
dnf config-manager --save --setopt=epel-nvidia-580.priority=90
dnf install -y --enablerepo="epel-nvidia-580" akmod-nvidia

dnf -y install gcc-c++
akmods --force --kernels "${KERNEL_VERSION}" --kmod "nvidia"
cat /var/cache/akmods/nvidia/*.failed.log || true

dnf config-manager --add-repo "https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo"
dnf config-manager --set-disabled "epel-nvidia-580"
dnf install -y --enablerepo="nvidia-container-toolkit" nvidia-container-toolkit

dnf install -y --enablerepo="epel-nvidia-580" --enablerepo="nvidia-container-toolkit" \
    "libnvidia-fbc" \
    "libnvidia-ml" \
    "nvidia-driver" \
    "nvidia-driver-cuda" 

tee /usr/lib/modprobe.d/00-nouveau-blacklist.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

echo zfs >/usr/lib/modules-load.d/zfs.conf
echo nvidia >/usr/lib/modules-load.d/nvidia.conf


tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# we must force driver load to fix black screen on boot for nvidia desktops
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

# as we need forced load, also mustpre-load intel/amd iGPU else chromium web browsers fail to use hardware acceleration
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible --zstd -v --add ostree -f "/lib/modules/$KERNEL_VERSION/initramfs.img"

sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/bootc update --quiet|' /usr/lib/systemd/system/bootc-fetch-apply-updates.service
systemctl enable bootc-fetch-apply-updates

dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf config-manager --set-disabled docker-ce-stable
dnf -y install --enablerepo='docker-ce-stable' docker-ce docker-ce-cli docker-compose-plugin

ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
mkdir -p /usr/lib/sysctl.d
echo "net.ipv4.ip_forward = 1" >/usr/lib/sysctl.d/docker-ce.conf

sed -i 's/enable docker/disable docker/' /usr/lib/systemd/system-preset/90-default.preset
systemctl preset docker.service docker.socket

cat >/usr/lib/sysusers.d/docker.conf <<'EOF'
g docker -
EOF

