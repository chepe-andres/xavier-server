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

# This forces DKMS to compress the compiled modules so the kernel can actually read them.
mkdir -p /etc/dkms
tee /etc/dkms/zstd.conf <<'EOF'
POST_BUILD="zstd --rm -f $dkms_tree/$module/$module_version/build/*.ko"
EOF

# Enable Negativo17
dnf config-manager --add-repo "https://negativo17.org/repos/epel-nvidia.repo"

# Install the drivers 
dnf install -y \
    nvidia-driver \
    nvidia-driver-cuda \
    nvidia-kmod-open-dkms \
    libnvidia-fbc \
    libnvidia-ml

# Add the NVIDIA Container Toolkit repo
dnf config-manager --add-repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo

# Install the toolkit
dnf install -y nvidia-container-toolkit

NVIDIA_VERSION=$(rpm -q --qf "%{VERSION}" nvidia-kmod-open-dkms)
dkms install -m nvidia -v "${NVIDIA_VERSION}" -k "${KERNEL_VERSION}"


tee /usr/lib/modprobe.d/00-nouveau-blacklist.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

echo zfs >/usr/lib/modules-load.d/zfs.conf
echo nvidia >/usr/lib/modules-load.d/nvidia.conf
echo nvidia-uvm >>/usr/lib/modules-load.d/nvidia.conf 

tee /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1"]
EOF

# we must force driver load to fix black screen on boot for nvidia desktops
sed -i 's@omit_drivers@force_drivers@g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf

# as we need forced load, also mustpre-load intel/amd iGPU else chromium web browsers fail to use hardware acceleration
sed -i 's@ nvidia @ i915 amdgpu nvidia @g' /usr/lib/dracut/dracut.conf.d/99-nvidia.conf


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

#tailscale
dnf config-manager --add-repo https://pkgs.tailscale.com/stable/centos/10/tailscale.repo
dnf -y  install tailscale

systemctl enable tailscaled



dnf install -y plymouth cockpit cockpit-storaged cockpit-ws cockpit-machines cockpit-selinux cockpit-files cockpit-storaged wget git firewalld msedit fastfetch btop
systemctl enable cockpit.socket










dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible --zstd -v --add ostree -f "/lib/modules/$KERNEL_VERSION/initramfs.img"
