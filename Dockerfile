FROM alpine:latest as builder
WORKDIR /root/vlmcsd
ADD . ./
RUN apk add --no-cache \
      make \
      build-base \
    && make

FROM alpine:latest
COPY --from=builder /root/vlmcsd/bin/vlmcsd /vlmcsd
COPY --from=builder /root/vlmcsd/etc/vlmcsd.kmd /vlmcsd.kmd
RUN apk add --no-cache tzdata

EXPOSE 1688/tcp

CMD ["/vlmcsd", "-D", "-d", "-t", "3", "-e", "-v"]
