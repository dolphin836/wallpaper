FROM golang:1.26-alpine AS builder

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
ENV GOPROXY=https://goproxy.cn,direct

# Worker needs cgo + libwebp to encode WebP. Other binaries stay pure-Go.
RUN apk add --no-cache gcc musl-dev libwebp-dev

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/api ./cmd/api
RUN CGO_ENABLED=1 go build -o /bin/worker ./cmd/worker
RUN CGO_ENABLED=0 go build -o /bin/sluggen ./cmd/sluggen
RUN CGO_ENABLED=0 go build -o /bin/phashgen ./cmd/phashgen
RUN CGO_ENABLED=0 go build -o /bin/setadmin ./cmd/setadmin
RUN CGO_ENABLED=0 go build -o /bin/recompress ./cmd/recompress
RUN CGO_ENABLED=0 go build -o /bin/autotag ./cmd/autotag
RUN CGO_ENABLED=0 go build -o /bin/tagclean ./cmd/tagclean
RUN CGO_ENABLED=0 go build -o /bin/qcheck ./cmd/qcheck
RUN CGO_ENABLED=0 go build -o /bin/indexnow-backfill ./cmd/indexnow-backfill
RUN CGO_ENABLED=0 go build -o /bin/weekly-drop ./cmd/weekly-drop
RUN CGO_ENABLED=0 go build -o /bin/wallpaper-import ./cmd/wallpaper-import

FROM alpine:3.19 AS api
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache ca-certificates tzdata
# tus tempdir for resumable video uploads. Mounted as a volume in
# docker-compose so the staging files persist across api container
# restarts (an upload paused in the browser can resume after we
# restart the api).
RUN mkdir -p /var/lib/wpe/tus
COPY --from=builder /bin/api /bin/api
COPY --from=builder /bin/sluggen /bin/sluggen
COPY --from=builder /bin/phashgen /bin/phashgen
COPY --from=builder /bin/setadmin /bin/setadmin
COPY --from=builder /bin/recompress /bin/recompress
COPY --from=builder /bin/autotag /bin/autotag
COPY --from=builder /bin/tagclean /bin/tagclean
COPY --from=builder /bin/qcheck /bin/qcheck
COPY --from=builder /bin/indexnow-backfill /bin/indexnow-backfill
COPY --from=builder /bin/weekly-drop /bin/weekly-drop
COPY --from=builder /bin/wallpaper-import /bin/wallpaper-import
ENTRYPOINT ["/bin/api"]

FROM alpine:3.19 AS worker
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache ca-certificates tzdata libheif-tools libwebp ffmpeg
# Scratch dir for the video transcode worker. Mounted as a volume in
# compose so concurrent transcodes don't fight for / disk space.
RUN mkdir -p /var/lib/wpe/transcode
COPY --from=builder /bin/worker /bin/worker
ENTRYPOINT ["/bin/worker"]
