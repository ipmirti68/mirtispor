FROM nginx:alpine

RUN apk add --no-cache ffmpeg curl coreutils dos2unix

RUN mkdir -p /app/live/cam0 /tmp

RUN cat > /etc/nginx/nginx.conf <<'NGINX_EOF'
user nginx;
worker_processes auto;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    send_timeout 60;
    client_max_body_size 0;
    access_log /dev/stdout;
    open_file_cache off;
    gzip off;

    server {
        listen 8080;
        server_name _;

        location = /health {
            default_type text/plain;
            return 200 "OK";
        }

        location ~ \.m3u8$ {
            root /app/live;
            types { application/vnd.apple.mpegurl m3u8; }
            default_type application/vnd.apple.mpegurl;
            add_header Access-Control-Allow-Origin "*" always;
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;
            try_files $uri =404;
        }

        location ~ \.ts$ {
            root /app/live;
            default_type video/mp2t;
            add_header Access-Control-Allow-Origin "*" always;
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;
            try_files $uri =404;
        }

        location / {
            root /app/live;
            index index.html;
            autoindex off;
            add_header Cache-Control "no-cache" always;
        }
    }
}
NGINX_EOF

RUN cat > /app/live_index.html <<'HTML_EOF'
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mirti Spor Canli Yayin</title>
<style>
body { background:#111; color:#fff; font-family:Arial; text-align:center; margin:0; padding:20px; }
video { width:95%; max-width:900px; background:#000; border:1px solid #333; }
a { color:#4da3ff; display:inline-block; margin-top:15px; }
#durum { color:#ffcc00; font-size:13px; margin-top:12px; }
</style>
</head>
<body>
<h2>MIRTI SPOR - CANLI YAYIN</h2>
<video id="v" controls autoplay muted playsinline></video>
<p><a href="cam0/index.m3u8">M3U8 YAYIN ADRESI</a></p>
<div id="durum">Yayin baglantisi hazirlaniyor...</div>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
<script>
const video = document.getElementById('v');
const durum = document.getElementById('durum');
if (window.Hls && Hls.isSupported()) {
  const hls = new Hls({ maxBufferLength: 30, maxMaxBufferLength: 60, liveSyncDurationCount: 3 });
  hls.loadSource('cam0/index.m3u8');
  hls.attachMedia(video);
  hls.on(Hls.Events.MANIFEST_PARSED, function() { video.play().catch(function(){}); });
} else if (video.canPlayType('application/vnd.apple.mpegurl')) {
  video.src = 'cam0/index.m3u8';
}
video.addEventListener('playing', function() { durum.textContent = "Yayin oynatiliyor"; });
</script>
</body>
</html>
HTML_EOF

RUN cat > /app/start.sh <<'START_EOF'
#!/bin/sh
set -u
mkdir -p /app/live/cam0 /tmp
cp /app/live_index.html /app/live/index.html


echo "MIRTI68 CANLI YAYIN - LOGOLU 480p"

rm -f /tmp/logo1.jpg
curl -fL -k --connect-timeout 10 --max-time 30 --retry 3 -o /tmp/logo1.jpg "https://raw.githubusercontent.com/ipmirti68/Logo/refs/heads/main/IMG-20261018-WA1513.jpg" || echo "[UYARI] Logo indirilemedi"

if ! ffmpeg -v error -i /tmp/logo1.jpg -frames:v 1 -f null - >/dev/null 2>&1; then
  ffmpeg -y -v error -f lavfi -i color=c=black:s=120x80 -frames:v 1 /tmp/logo1.jpg
fi

YAYIN="http://31.43.191.125:8080/VIP01361740328055349/dd5808c9dede/141357"
REFERER=""
ORIGIN=""
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

echo "[NGINX] Baslatiliyor..."
nginx

BEKLE=2
TUR=1

while true; do
  echo "TUR $TUR BASLIYOR"
  rm -f /app/live/cam0/seg_*.ts /app/live/cam0/index.m3u8
  BASLANGIC=$(date +%s)

  ffmpeg -hide_banner -loglevel warning \
    -fflags +discardcorrupt+genpts \
    -rw_timeout 15000000 \
    -thread_queue_size 1024 \
    -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 -reconnect_on_network_error 1 \
    -headers "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36\r\nReferer: https://mahsunsports15.xyz/\r\nOrigin: https://mahsunsports15.xyz\r\n" \
    -user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
    -referer "" \
    -probesize 10M -analyzeduration 10M \
    -i "$YAYIN" \
    -loop 1 -framerate 25 -i /tmp/logo1.jpg \
    -filter_complex "[0:v]fps=25,scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p[base];[1:v]scale=110:-1[lg];[base][lg]overlay=W-w-35:25:eof_action=pass[v]" \
    -map "[v]" -map 0:a? \
    -max_muxing_queue_size 2048 \
    -fps_mode cfr \
    -af aresample=44100:async=1000 \
    -c:v libx264 \
    -preset ultrafast \
    -tune zerolatency \
    -profile:v main \
    -pix_fmt yuv420p \
    -b:v 800k \
    -maxrate 1000k \
    -bufsize 1600k \
    -g 100 \
    -keyint_min 100 \
    -sc_threshold 0 \
    -c:a aac \
    -b:a 64k \
    -ar 44100 -ac 2 \
    -f hls \
    -hls_time 4 \
    -hls_list_size 8 \
    -hls_delete_threshold 4 \
    -hls_allow_cache 0 \
    -hls_start_number_source epoch \
    -hls_flags delete_segments+independent_segments+program_date_time+temp_file \
    -hls_segment_type mpegts \
    -hls_segment_filename "/app/live/cam0/seg_%d.ts" \
    /app/live/cam0/index.m3u8 &

  FFPID=$!
  echo "[FFMPEG] PID: $FFPID"

  while kill -0 "$FFPID" 2>/dev/null; do
    sleep 10
    SIMDI=$(date +%s)
    SON_SEGMENT=0
    for DOSYA in /app/live/cam0/seg_*.ts; do
      [ -f "$DOSYA" ] || continue
      ZAMAN=$(stat -c %Y "$DOSYA" 2>/dev/null || echo 0)
      if [ "$ZAMAN" -gt "$SON_SEGMENT" ]; then SON_SEGMENT=$ZAMAN; fi
    done
    if [ "$SON_SEGMENT" -eq 0 ]; then
      GECEN=$((SIMDI - BASLANGIC))
    else
      GECEN=$((SIMDI - SON_SEGMENT))
    fi
    TOPLAM=$((SIMDI - BASLANGIC))
    if [ "$GECEN" -ge 35 ]; then
      echo "[DONMA] $GECEN saniyedir yeni segment yok"
      break
    fi
    if [ "$TOPLAM" -ge 3000 ]; then
      echo "[RESET] 50 dakika doldu"
      break
    fi
    echo "[DURUM] Segment: ${GECEN}s"
  done

  kill -TERM "$FFPID" 2>/dev/null || true
  sleep 2
  kill -KILL "$FFPID" 2>/dev/null || true
  wait "$FFPID" 2>/dev/null || true

  echo "[BAGLANTI] $BEKLE saniye sonra yeniden denenecek."
  sleep "$BEKLE"
  if [ "$BEKLE" -lt 16 ]; then BEKLE=$((BEKLE * 2)); else BEKLE=10; fi
  TUR=$((TUR + 1))
done
START_EOF

RUN dos2unix /app/start.sh && chmod +x /app/start.sh

EXPOSE 8080

CMD ["/bin/sh", "/app/start.sh"]
