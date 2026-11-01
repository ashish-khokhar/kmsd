FROM alpine:3.24 AS builder
WORKDIR /root/vlmcsd
COPY . ./
RUN apk add --no-cache \
      make \
      build-base \
    && make

FROM alpine:3.24

# Create an unprivileged account to run the service. vlmcsd listens on 1688/tcp
# (an unprivileged port) and the default CMD writes no files, so it does not need root.
RUN apk add --no-cache tzdata \
    && addgroup -S vlmcsd \
    && adduser -S -D -H -G vlmcsd vlmcsd

COPY --from=builder /root/vlmcsd/bin/vlmcsd /vlmcsd
COPY --from=builder /root/vlmcsd/etc/vlmcsd.kmd /vlmcsd.kmd

# Drop privileges: the server runs as a non-root user.
USER vlmcsd

EXPOSE 1688/tcp

CMD ["/vlmcsd", "-D", "-d", "-t", "3", "-e", "-v"]
