sudo podman pull ghcr.io/chepe-andres/homeserver:latest
mkdir output
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./config.toml:/config.toml:ro \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type iso \
    --use-librepo=True \
    --rootfs ext4 \
    ghcr.io/chepe-andres/homeserver:latest