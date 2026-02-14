#!/bin/bash
set -e

# =================CONFIGURATION=================
SAGE_REPO="https://github.com/sagemath/sage.git"
IMAGE_TAG="sage-32bit-builder"
CONTAINER_NAME="sage-builder-tmp"
# Define a builder name to avoid conflicts
BUILDER_NAME="sage-proxy-builder"
PROXY_PORT=7897
IMAGES="$(dirname "$0")"/../../../images
OUT_ROOTFS_TAR="$IMAGES"/debian-9p-rootfs.tar
OUT_ROOTFS_FLAT="$IMAGES"/debian-9p-rootfs-flat
OUT_FSJSON="$IMAGES"/debian-base-fs.json


# DETECT HOST IP
HOST_IP=$(hostname -I | awk '{print $1}')

if [ -z "$HOST_IP" ]; then
    echo "Error: Could not detect Host IP. Please set HOST_IP manually in the script."
    exit 1
fi

PROXY_URL="http://${HOST_IP}:${PROXY_PORT}"
# ===============================================

# Cleanup
rm -f Dockerfile.32bit
mkdir -p "$IMAGES"

echo "Generating Dockerfile..."

# Generate 32-bit Dockerfile
cat <<EOF > Dockerfile.32bit
FROM i386/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# --- MODIFICATION START: Force Generic 32-bit CPU ---
ENV CFLAGS="-O2 -march=i686 -mtune=generic -m32"
ENV CXXFLAGS="-O2 -march=i686 -mtune=generic -m32"
ENV LDFLAGS="-m32"
ENV SAGE_FAT_BINARY=yes
# Force OpenBLAS to build for a generic target (Core2 is a safe baseline)
ENV OPENBLAS_CONFIGURE="TARGET=CORE2 DYNAMIC_ARCH=0"
ENV FFLASFFPACK_CONFIGURE="--disable-simd --disable-avx --disable-avx2 --disable-fma3"
# --- MODIFICATION END ---

# Configure Mirrors
RUN rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware\n\
    deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware\n\
    deb http://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware\n\
    deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    linux-image-686 \
    systemd-sysv \
    locales \
    libterm-readline-perl-perl \

RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    chsh -s /bin/bash root  

# Install Dependencies (NO PROXY USED HERE)
# Docker runs this layer entirely without the proxy, relying on Tuna speed.
RUN apt-get -o Acquire::Check-Valid-Until=false update && \\
    apt-get install -y --no-install-recommends \\
    ca-certificates curl git build-essential \\
    libterm-readline-perl-perl bc binutils bzip2 cmake \\
    libgsl-dev \\
    ecl eclib-tools fflas-ffpack flex g++ gap gcc gengetopt gfan gfortran \\
    glpk-utils gmp-ecm lcalc libatomic-ops-dev libboost-dev libbraiding-dev \\
    libbrial-dev libbrial-groebner-dev libbz2-dev libcdd-dev libcdd-tools \\
    libcliquer-dev libcurl4-openssl-dev libec-dev libecm-dev libffi-dev \\
    libflint-dev libfplll-dev libfreetype-dev libgap-dev libgc-dev libgd-dev \\
    libgf2x-dev libgivaro-dev libglpk-dev libgmp-dev libgsl-dev \\
    libhomfly-dev libiml-dev liblfunction-dev liblinbox-dev liblrcalc-dev \\
    liblzma-dev libm4ri-dev libm4rie-dev libmpc-dev libmpfi-dev libmpfr-dev \\
    libncurses-dev libntl-dev libpari-dev libplanarity-dev \\
    libppl-dev libprimecount-dev libprimesieve-dev libpython3-dev \\
    libqhull-dev libreadline-dev librw-dev libsingular4-dev libsqlite3-dev \\
    libssl-dev libsuitesparse-dev libsymmetrica-dev libz-dev libzmq3-dev m4 \\
    make maxima maxima-sage meson nauty ninja-build openssl palp pari-doc \\
    pari-elldata pari-galdata pari-galpol pari-gp2c pari-seadata patch \\
    patchelf perl pkg-config planarity ppl-dev python3 python3-setuptools \\
    python3-venv qhull-bin singular singular-doc sqlite3 sympow tachyon tar \\
    texinfo tox xz-utils autoconf automake gh gpgconf libtool openssh-client \\
    4ti2 clang coinor-cbc coinor-libcbc-dev fricas graphviz \\
    libfile-slurp-perl libgiac-dev libgraphviz-dev libigraph-dev libisl-dev \\
    libjson-perl libmongodb-perl libnauty-dev libperl-dev libpolymake-dev \\
    libsvg-perl libtbb-dev libterm-readkey-perl libterm-readline-gnu-perl \\
    libxml-libxslt-perl libxml-writer-perl libxml2-dev lrslib \\
    pdf2svg polymake sbcl xcas \\
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------
# ENABLE PROXY FOR GIT AND SAGEMATH BUILD
# By setting ENV here, everything below this line uses the proxy
# -----------------------------------------------------------
ARG PROXY_URL
ENV http_proxy=\${PROXY_URL}
ENV https_proxy=\${PROXY_URL}
ENV HTTP_PROXY=\${PROXY_URL}
ENV HTTPS_PROXY=\${PROXY_URL}

# Clone SageMath
WORKDIR /root/build
RUN git clone -c core.symlinks=true --filter blob:none --origin upstream --branch master --tags $SAGE_REPO sage

# Build SageMath
WORKDIR /root/build/sage
RUN make configure
RUN ./configure --prefix=/usr/local \\
                --build=i686-linux-gnu \\
                --with-system-python3=yes \\
                --with-system-gmp=yes \\
                --with-system-mpfr=yes \\
                --with-system-flint=yes \\
                --with-system-gsl=yes \\
                --enable-build-as-root \\
                --disable-doc

# Parallel build (-j2 is safe for 32-bit builds)
RUN make -j2
RUN make install

# Reset Proxy
ENV http_proxy=""
ENV https_proxy=""
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

# Fix root password and pam
RUN passwd -d root && \
    sed -i 's/nullok_secure/nullok/' /etc/pam.d/common-auth

# Configure Serial Console (Autologin)
COPY getty-noclear.conf getty-override.conf /etc/systemd/system/getty@tty1.service.d/
COPY getty-autologin-serial.conf /etc/systemd/system/serial-getty@ttyS0.service.d/

RUN systemctl mask console-getty.service && \
    systemctl enable serial-getty@ttyS0.service

# Disable Unnecessary Services (Boot Speed)
RUN systemctl disable systemd-timesyncd.service && \
    systemctl disable apt-daily.timer && \
    systemctl disable apt-daily-upgrade.timer

RUN printf '%s\n' 9p 9pnet 9pnet_virtio virtio virtio_ring virtio_pci | tee -a /etc/initramfs-tools/modules

RUN echo '#!/bin/sh' > /etc/initramfs-tools/scripts/boot-9p && \
    echo 'case \$1 in prereqs) exit 0;; esac' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo '. /scripts/functions' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mkdir -p \${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mount -n -t 9p -o trans=virtio,version=9p2000.L,cache=loose,rw host9p \${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    chmod +x /etc/initramfs-tools/scripts/boot-9p


RUN echo 'BOOT=boot-9p' | tee -a /etc/initramfs-tools/initramfs.conf

RUN update-initramfs -u

# Add Sage to startup path
RUN echo "/usr/local/bin/sage" >> /root/.bashrc

WORKDIR /root
EOF

# Build the Image
echo "--------------------------------------------------------"
echo "Building Docker Image..."
echo "Detected Host IP: $HOST_IP"
echo "Proxy will activate AFTER apt-get install: $PROXY_URL"
echo "--------------------------------------------------------"
echo "Ensure 'Allow LAN' is ENABLED in Clash!"
echo "--------------------------------------------------------"

# Notice we use --build-arg PROXY_URL instead of http_proxy.
# This prevents Docker from forcing the proxy on the apt-get layers above it.

# 1. Clean up old builder
docker buildx rm "$BUILDER_NAME" 2>/dev/null || true

# 2. FIX: Configure builder with Proxy so it can pull the base image
docker buildx create \
  --name "$BUILDER_NAME" \
  --driver docker-container \
  --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
  --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
  --driver-opt env.http_proxy="$PROXY_URL" \
  --driver-opt env.https_proxy="$PROXY_URL" \
  --use

docker buildx build \
    --load \
    --progress=plain \
    --platform linux/386 \
    -f Dockerfile.32bit \
    -t "$IMAGE_TAG" \
    --build-arg PROXY_URL="$PROXY_URL" \
    .

# Export Docker

docker rm -f "$CONTAINER_NAME" || true
docker create --platform linux/386 --name "$CONTAINER_NAME" "$IMAGE_TAG"
docker export "$CONTAINER_NAME" > "$OUT_ROOTFS_TAR"

rm Dockerfile.32bit

echo "Converting to JSON..."
"$(dirname "$0")"/../../../tools/fs2json.py --zstd --out "$OUT_FSJSON" "$OUT_ROOTFS_TAR"

echo "Creating flat filesystem..."
# Clear old files to prevent conflicts
rm -rf "$OUT_ROOTFS_FLAT"
mkdir -p "$OUT_ROOTFS_FLAT"
"$(dirname "$0")"/../../../tools/copy-to-sha256.py --zstd "$OUT_ROOTFS_TAR" "$OUT_ROOTFS_FLAT"

echo "Done. Artifacts created at $IMAGES"