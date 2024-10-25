ARG TAG=bookworm
ARG DEBIAN_FRONTEND=noninteractive
FROM debian:${TAG} as base

RUN echo 'debconf debconf/frontend select teletype' | debconf-set-selections

RUN apt-get update
RUN apt-get dist-upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -y install wget jq curl


RUN apt-get clean
RUN rm -rf                        \
    /var/lib/apt/lists/*          \
    /var/log/alternatives.log     \
    /var/log/apt/history.log      \
    /var/log/apt/term.log         \
    /var/log/dpkg.log

RUN rm -f           \
    /etc/machine-id \
    /var/lib/dbus/machine-id

RUN mkdir -p /opt
RUN mkdir -p /opt/config

FROM base AS add
ADD --chmod=777 files* /opt/
RUN chmod -R 777 /opt

WORKDIR /opt
CMD ["/opt/y.sh"]
