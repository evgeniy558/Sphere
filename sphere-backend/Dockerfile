FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /sphere ./cmd/server

# Runtime: Alpine + ffmpeg + yt-dlp only.
# onnxruntime/librosa do not publish reliable musl wheels on Alpine; NodeX ONNX
# inference is optional (karaoke falls back to ffmpeg when /models/nodex_vocal.onnx is absent).
FROM alpine:3.19
RUN apk add --no-cache ca-certificates ffmpeg python3 py3-pip \
    && pip install --no-cache-dir --break-system-packages -U "yt-dlp>=2025.1.15" \
    && yt-dlp --version

COPY --from=builder /sphere /sphere
COPY scripts/nodex/vocal/ /app/scripts/nodex/vocal/
RUN mkdir -p /models
EXPOSE 8080
CMD ["/sphere"]
