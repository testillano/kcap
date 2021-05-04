ARG base_tag=latest
# trace_visualizer.py fails on alpine, we need ubuntu:
FROM ubuntu:${base_tag}
MAINTAINER testillano

LABEL testillano.kcap.description="Docker image to ease kubernetes traffic captures and http2 analysis"

WORKDIR /kcap

ARG plantumljar_ver=1.2021.4

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    wget curl \
    python3 python3-pip \
    default-jdk \
    net-tools tshark

RUN pip3 install hpack packaging pyyaml

# plantuml.jar
RUN set -x && \
    wget http://sourceforge.net/projects/plantuml/files/plantuml.${plantumljar_ver}.jar/download -O plantuml.jar && \
    set +x

## kubectl
#RUN set -x && \
#    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
#    install -m 0755 kubectl /usr/local/bin/kubectl && \
#    set +x

# Build script
COPY deps/* /kcap/
RUN chmod a+x /kcap/*.sh

CMD [ "sleep", "infinity" ]

