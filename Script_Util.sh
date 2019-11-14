#!/bin/bash
if [ "$DEBUG" == "1" ]; then
    set -x
fi

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
exiterr2() { exiterr "'apk add' failed."; }
bigecho()  { echo; echo -e "\033[36m $1 \033[0m"; }

# Build chinadns
if ! type chinadns 2>/dev/null; then
    bigecho "Build chinadns, Pleast wait..."
    CHINADNS_VER=1.3.2
    CHINADNS_FILE="chinadns-$CHINADNS_VER"
    CHINADNS_URL="https://github.com/shadowsocks/ChinaDNS/releases/download/$CHINADNS_VER/$CHINADNS_FILE.tar.gz"
    if ! curl -sSL -o $CHINADNS_FILE.tar.gz $CHINADNS_URL; then
        bigecho "Failed to download file!"
        exit 1
    fi
    tar zxf $CHINADNS_FILE.tar.gz
    pushd $CHINADNS_FILE
    ./configure
    make && make install
    popd

    rm -rf $CHINADNS_FILE.tar.gz $CHINADNS_FILE
fi

# Build chinadns-ng
# Dependency: linux-headers build-base
if ! type chinadns-ng 2>/dev/null; then
    bigecho "Build chinadns-ng, Pleast wait..."
    CHINADNS_NG_FILE="chinadns-ng-master"
    CHINADNS_NG_URL="https://github.com/zfl9/chinadns-ng/archive/master.tar.gz"
    if ! curl -sSL -o $CHINADNS_NG_FILE.tar.gz $CHINADNS_NG_URL; then
        bigecho "Failed to download file!"
        exit 1
    fi
    tar zxf $CHINADNS_NG_FILE.tar.gz
    pushd $CHINADNS_NG_FILE
    make && make install
    popd
    rm -rf $CHINADNS_NG_FILE.tar.gz $CHINADNS_NG_FILE
fi

# Install Script_Util
if ! type ss-tproxy 2>/dev/null; then
    bigecho "Install SS-Proxy, Pleast wait..."
    git clone https://github.com/worksg/ss-tproxy.git
    pushd ss-tproxy
    cp -af ss-tproxy /usr/local/bin
	chmod 0755 /usr/local/bin/ss-tproxy
	chown root:root /usr/local/bin/ss-tproxy
	mkdir -m 0755 -p /etc/ss-tproxy
	cp -af ss-tproxy.conf gfwlist* chnroute* /etc/ss-tproxy
	chmod 0644 /etc/ss-tproxy/* && chown -R root:root /etc/ss-tproxy
    popd

    rm -rf ss-tproxy
fi

# Display info
bigecho "#######################################################"
bigecho "Please modify /etc/tproxy/ss-tproxy.conf before start."
bigecho "#ss-tproxy start"
bigecho "#######################################################"

# ss-tproxy update-gfwlist
# ss-tproxy update-chnroute 
# ss-tproxy update-chnlist
# ss-tproxy restart