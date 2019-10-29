FROM alpine:latest as base

LABEL maintainer=mmiller@bromberglab.org \
      description="bio-node base image"

FROM base as builder

# setup system
RUN mkdir /install
WORKDIR /install
RUN apk update && apk add alpine-sdk && rm -rf /var/cache/apk/*

# setup bio-node
COPY . /bio-node

RUN git clone https://github.com/bromberglab/bash-template.git && \
    mv bash-template/bio-node.sh /bio-node && \
    git clone https://github.com/bromberglab/python-template.git && \
    mv python-template/bio-node.py /bio-node

FROM base

COPY --from=builder /bio-node /bio-node

# set environment variables
WORKDIR /bio-node
