FROM i386/debian:bookworm-slim

WORKDIR /root/build
ENV DEBIAN_FRONTEND noninteractive

# 1. Base Setup (Mirrors + Kernel + Systemd)
# We install linux-image-686 for the kernel and systemd-sysv for init.
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
    && rm -rf /var/lib/apt/lists/* 

# 2. Configure Locales & Shell
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    chsh -s /bin/bash root  

# 3. Install sagemath
# We install it here to keep the layer clean
RUN apt-get update && \
    apt-get install -y --no-install-recommends sagemath && \
    rm -rf /var/lib/apt/lists/*

RUN passwd -d root && \
    sed -i 's/nullok_secure/nullok/' /etc/pam.d/common-auth

# 4. Configure Serial Console (Autologin)
COPY getty-noclear.conf getty-override.conf /etc/systemd/system/getty@tty1.service.d/
COPY getty-autologin-serial.conf /etc/systemd/system/serial-getty@ttyS0.service.d/

RUN systemctl enable serial-getty@ttyS0.service

# 5. Disable Unnecessary Services (Boot Speed)
RUN systemctl disable systemd-timesyncd.service && \
    systemctl disable apt-daily.timer && \
    systemctl disable apt-daily-upgrade.timer

# ------------------------------------------------------------------------------
# 6. CRITICAL: 9p Filesystem Boot Configuration
# ------------------------------------------------------------------------------

# A. Add required modules to initramfs
RUN printf '%s\n' 9p 9pnet 9pnet_virtio virtio virtio_ring virtio_pci | tee -a /etc/initramfs-tools/modules

# B. Create the custom boot script (boot-9p)
# This script tells initramfs how to mount the v86 filesystem tag 'host9p'
RUN echo '#!/bin/sh' > /etc/initramfs-tools/scripts/boot-9p && \
    echo 'case $1 in prereqs) exit 0;; esac' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo '. /scripts/functions' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mkdir -p ${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mount -n -t 9p -o trans=virtio,version=9p2000.L,cache=loose,rw host9p ${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    chmod +x /etc/initramfs-tools/scripts/boot-9p

# C. Configure initramfs to use our boot script
RUN echo 'BOOT=boot-9p' | tee -a /etc/initramfs-tools/initramfs.conf

# D. Regenerate initramfs with these changes
RUN update-initramfs -u

RUN echo "sage" >> /root/.bashrc

WORKDIR /root