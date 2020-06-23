# unbound
FROM alpine:edge as unbound_builder

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories

RUN adduser \
    -S -H -D \
    -h /home/builder \
    -s /bin/bash \
    -u 1000 \
    -G abuild \
    -g "Alpine Package Builder" \
    builder && \
    echo "builder:$(dd if=/dev/urandom bs=24 count=1 status=none | base64)" | chpasswd

RUN set -ex \
    && apk --update add --no-cache alpine-sdk coreutils cmake bash wget git sudo \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && mkdir -p /home/builder/packages  \
    && chown builder:abuild /home/builder/packages /home/builder

USER builder

RUN set -ex && mkdir ~/unbound \
    && cd ~/unbound && git init && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/APKBUILD && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/migrate-dnscache-to-unbound && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/conf.patch && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/unbound.confd && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/unbound.initd && \
    curl -LO https://git.alpinelinux.org/aports/plain/main/unbound/unbound.pre-install \
    && echo -e '\n' | abuild-keygen -a \
    && sed -i 's#--with-pyunbound#--with-pyunbound --enable-subnet#g' APKBUILD \
    # update package info
    && sudo apk update \
    && abuild -r \
    && ls -la /home/builder/packages/builder/x86_64/

FROM golang:alpine as go_builder

RUN apk --update add --no-cache tar git wget curl

ENV DNSPROXY_VERSION=0.29.0

ENV GO111MODULE=on \
    CGO_ENABLED=0

ENV DOH_GIT_URL="https://github.com/m13253/dns-over-https"
ENV TCPING_GIT_URL="https://github.com/worksg/tcping"
ENV DNSPROXY_DOWNLOAD_URL="https://github.com/AdguardTeam/dnsproxy/archive/v${DNSPROXY_VERSION}.tar.gz"
ENV OVERTURE_GIT_URL="https://github.com/worksg/overture"

RUN set -ex \
    && git clone ${DOH_GIT_URL} \
    && (cd dns-over-https \
    && go mod download \
    && go build -ldflags "-s -w" -o doh-client-linux-x64 github.com/m13253/dns-over-https/doh-client \
    && mv -f doh-client-linux-x64 /usr/bin/dohclient \
    && go build -ldflags "-s -w" -o doh-server-linux-x64 github.com/m13253/dns-over-https/doh-server \
    && mv -f doh-server-linux-x64 /usr/bin/dohserver ) \
    && rm -rf dns-over-https

RUN set -ex \
    && git clone ${TCPING_GIT_URL} \
    && (cd tcping \
    && go mod download \
    && go build -o tcping -ldflags "-s -w" github.com/cloverstd/tcping \
    && chmod +x tcping \
    && mv -f tcping /usr/bin/tcping ) \
    && rm -rf tcping

RUN set -ex \
    && git clone ${OVERTURE_GIT_URL} \
    && (cd overture \
    && go mod download \
    && go build -o overture -ldflags "-s -w" github.com/shawn1m/overture/main \
    && chmod +x overture \
    && mv -f overture /usr/bin/overture ) \
    && rm -rf overture

RUN set -ex \
    && curl -L ${DNSPROXY_DOWNLOAD_URL} -o dnsproxy-${DNSPROXY_VERSION}.tar.gz \
    && mkdir dnsproxy_source \
    && tar zxf dnsproxy-${DNSPROXY_VERSION}.tar.gz -C dnsproxy_source \
    && (cd dnsproxy_source/dnsproxy-${DNSPROXY_VERSION} \
    && go build -ldflags "-s -w" \
    && chmod +x dnsproxy \
    && mv -f dnsproxy /usr/bin/dnsproxy ) \
    && rm -rf dnsproxy_source dnsproxy-${DNSPROXY_VERSION}.tar.gz

# Smallest base image
FROM alpine:edge

LABEL maintainer "worksg <571940753@qq.com>"

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories \
    && echo "http://nginx.org/packages/mainline/alpine/v3.12/main" >> /etc/apk/repositories

# == WireGuard ==
RUN apk add -U wireguard-tools supervisor

COPY --from=unbound_builder /home/builder/packages/builder/x86_64/* /unbound-main-apk/

RUN set -ex \
    && apk add --allow-untrusted /unbound-main-apk/*.apk && rm -rf /unbound-main-apk \
    && apk --update add --no-cache \
    ca-certificates iproute2 ipset perl knot-utils net-tools dnsmasq curl wget netcat-openbsd moreutils \
    dhclient libqrencode ip6tables iptables \
    # https://nginx.org/en/linux_packages.html#Alpine
    && curl -o /etc/apk/keys/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
    && apk add --no-cache nginx

RUN set -ex \
    && apk upgrade \
    && apk add bash tzdata libsodium rng-tools \
    && apk add --virtual .build-deps \
    autoconf \
    automake \
    xmlto \
    build-base \
    c-ares-dev \
    libev-dev \
    libtool \
    linux-headers \
    udns-dev \
    libsodium-dev \
    mbedtls-dev \
    pcre-dev \
    udns-dev \
    tar \
    git

SHELL ["/bin/bash", "-c"]

# == Shadowsocks KCP OBFS ==
ARG TZ='Asia/Hong_Kong'

ENV TZ=$TZ \
    SS_LIBEV_VERSION=3.3.4 \
    KCP_VERSION=20200409

ENV KCP_DOWNLOAD_URL="https://github.com/xtaci/kcptun/releases/download/v${KCP_VERSION}/kcptun-linux-amd64-${KCP_VERSION}.tar.gz" \
    SS_DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-libev/releases/download/v${SS_LIBEV_VERSION}/shadowsocks-libev-${SS_LIBEV_VERSION}.tar.gz" \
    OBFS_DOWNLOAD_URL="https://github.com/shadowsocks/simple-obfs.git"

RUN set -ex \
    && curl -LO ${SS_DOWNLOAD_URL} \
    && tar -zxf shadowsocks-libev-${SS_LIBEV_VERSION}.tar.gz \
    && (cd shadowsocks-libev-${SS_LIBEV_VERSION} \
    && ./configure --prefix=/usr --disable-documentation \
    && make install) \
    && git clone ${OBFS_DOWNLOAD_URL} \
    && (cd simple-obfs \
    && git submodule update --init --recursive \
    && ./autogen.sh && ./configure --disable-documentation\
    && make && make install) \
    && curl -LO ${KCP_DOWNLOAD_URL} \
    && tar -zxf kcptun-linux-amd64-${KCP_VERSION}.tar.gz \
    && mv server_linux_amd64 /usr/bin/kcpserver \
    && mv client_linux_amd64 /usr/bin/kcpclient \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && runDeps="$( \
    scanelf --needed --nobanner /usr/bin/ss-* /usr/local/bin/obfs-* \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | xargs -r apk info --installed \
    | sort -u \
    )" \
    && rngd -r /dev/urandom \
    && apk add --virtual .run-deps $runDeps

COPY SS_Entrypoint.sh /SS_Entrypoint.sh
RUN chmod a+x /SS_Entrypoint.sh

# == Script_Util ==
COPY Script_Util.sh /Script_Util.sh
RUN chmod a+x /Script_Util.sh && /Script_Util.sh

# == GOST UDPSPEEDER UDP2RAW V2RAY ==
ENV GOST_VERSION=2.11.1 \
    UDP2RAW_VERSION=20181113.0 \
    V2RAY_VERSION=4.25.0 \
    UDPSPEEDER_VERSION=20190121.0 \
    V2RAY_PLUGIN_VERSION=1.3.1

ENV GOST_DOWNLOAD_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-amd64-${GOST_VERSION}.gz" \
    UDP2RAW_DOWNLOAD_URL="https://github.com/wangyu-/udp2raw-tunnel/releases/download/${UDP2RAW_VERSION}/udp2raw_binaries.tar.gz" \
    V2RAY_DOWNLOAD_URL="https://github.com/v2ray/v2ray-core/releases/download/v${V2RAY_VERSION}/v2ray-linux-64.zip" \
    UDPSPEEDER_DOWNLOAD_URL="https://github.com/wangyu-/UDPspeeder/releases/download/${UDPSPEEDER_VERSION}/speederv2_binaries.tar.gz" \
    V2RAY_PLUGIN_DOWNLOAD_URL="https://github.com/shadowsocks/v2ray-plugin/releases/download/v${V2RAY_PLUGIN_VERSION}/v2ray-plugin-linux-amd64-v${V2RAY_PLUGIN_VERSION}.tar.gz"

RUN set -ex \
    && curl -LO ${GOST_DOWNLOAD_URL} \
    && gzip -d gost-linux-amd64-${GOST_VERSION}.gz \
    && chmod +x gost-linux-amd64-${GOST_VERSION} \
    && mv gost-linux-amd64-${GOST_VERSION} /usr/bin/gost

RUN set -ex \
    && curl -LO ${UDP2RAW_DOWNLOAD_URL} \
    && mkdir udp2raw_linux_amd64 \
    && tar zxf udp2raw_binaries.tar.gz -C udp2raw_linux_amd64 \
    && (cd udp2raw_linux_amd64 \
    && chmod +x udp2raw_amd64 \
    && mv udp2raw_amd64 /usr/bin/udp2raw)

RUN set -ex \
    && curl -LO ${V2RAY_DOWNLOAD_URL} \
    && mkdir v2ray_linux_amd64 /usr/bin/v2ray /etc/v2ray \
    && unzip -qo v2ray-linux-64.zip -d v2ray_linux_amd64 \
    && (cd v2ray_linux_amd64 \
    && chmod +x v2ray v2ctl \
    && mv config.json /etc/v2ray/config.json \
    && mv v2ray /usr/bin/v2ray/ \
    && mv v2ctl /usr/bin/v2ray/ \
    && mv geoip.dat /usr/bin/v2ray/ \
    && mv geosite.dat /usr/bin/v2ray/)

RUN set -ex \
    && curl -LO ${UDPSPEEDER_DOWNLOAD_URL} \
    && mkdir udpspeeder_linux_amd64 \
    && tar zxf speederv2_binaries.tar.gz -C udpspeeder_linux_amd64 \
    && (cd udpspeeder_linux_amd64 \
    && chmod +x speederv2_amd64 \
    && mv speederv2_amd64 /usr/bin/udpspeeder)

RUN set -ex \
    && curl -LO ${V2RAY_PLUGIN_DOWNLOAD_URL} \
    && mkdir v2ray-plugin_linux_amd64 \
    && tar zxf v2ray-plugin-linux-amd64-v${V2RAY_PLUGIN_VERSION}.tar.gz -C v2ray-plugin_linux_amd64 \
    && (cd v2ray-plugin_linux_amd64 \
    && chmod +x v2ray-plugin_linux_amd64 \
    && mv v2ray-plugin_linux_amd64 /usr/bin/v2ray-plugin)

ENV PATH /usr/bin/v2ray:$PATH

# == DNS Over HTTPS / TCPING / DNSPROXY / OVERTURE ==
COPY --from=go_builder /usr/bin/doh* /usr/bin/dnsproxy /usr/bin/overture /usr/bin/tcping /usr/bin/

RUN set -ex \
    && chmod +x /usr/bin/doh* /usr/bin/tcping /usr/bin/dnsproxy \
    && mkdir -p /etc/dns-over-https \
    && curl -L https://raw.githubusercontent.com/m13253/dns-over-https/master/doh-server/doh-server.conf \
    -o /etc/dns-over-https/doh-server.conf \
    && curl -L https://raw.githubusercontent.com/m13253/dns-over-https/master/doh-client/doh-client.conf \
    -o /etc/dns-over-https/doh-client.conf

# update chnroute / china_domains / gfw_domains
RUN ss-tproxy update-chnroute \
    && \
    curl -4sSL 'https://github.com/worksg/IP-UPDATE/raw/master/addr_ipv4.tar.gz' \
    | tar zxf - -O > /etc/ss-tproxy/chnroute.txt \
    && \
    ss-tproxy update-chnlist \
    && cp /etc/ss-tproxy/gfwlist.txt /etc/ss-tproxy/chinalist.txt \
    && \
    ss-tproxy update-gfwlist

RUN apk del .build-deps \
    && rm -rf kcptun-linux-amd64-${KCP_VERSION}.tar.gz \
    shadowsocks-libev-${SS_LIBEV_VERSION}.tar.gz \
    shadowsocks-libev-${SS_LIBEV_VERSION} \
    simple-obfs \
    v2ray_linux_amd64 \
    udp2raw_linux_amd64 \
    gost_linux_amd64 \
    udpspeeder_linux_amd64 \
    v2ray-linux-64.zip \
    udp2raw_binaries.tar.gz \
    speederv2_binaries.tar.gz \
    v2ray-plugin_linux_amd64 \
    v2ray-plugin-linux-amd64-v${V2RAY_PLUGIN_VERSION}.tar.gz \
    /var/cache/apk/* ~/.gitconfig ~/.wget-hsts

CMD [ "/bin/bash", "-c", "sleep infinity" ]
