FROM nginx:alpine

# ==========================================
# GEREKLI PROGRAMLAR
# ==========================================
RUN apk add --no-cache ffmpeg curl coreutils dos2unix

RUN mkdir -p /app/live/cam0 /tmp

# ==========================================
# NGINX AYARLARI
# ==========================================
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
            add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS" always;
            add_header Access-Control-Allow-Headers "*" always;
            add_header Cache-Control "no-cache, no-store, must-revalidate" always;
            add_header Pragma "no-cache" always;
            add_header Expires "0" always;
            if ($request_method = OPTIONS) { return 204; }
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

# ==========================================
# HTML OYNATICI
# ==========================================
RUN cat > /app/live_index.html <<'HTML_EOF'
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mirti Spor Canli Yayin</title>
<style>
*{box-sizing:border-box}
body{background:#111;color:#fff;font-family:Arial;text-align:center;margin:0;padding:20px}
h2{margin-bottom:20px}
video{width:95%;max-width:900px;background:#000;border:1px solid #333}
a{color:#4da3ff;display:inline-block;margin-top:15px}
#durum{color:#ffcc00;font-size:13px;margin-top:12px}
</style>
</head>
<body>
<h2>MIRTI SPOR - CANLI YAYIN</h2>
<video id="v" controls autoplay muted playsinline></video>
<p><a href="cam0/index.m3u8">M3U8 YAYIN ADRESI</a></p>
<div id="durum">Yayin baglantisi hazirlaniyor...</div>
<script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
<script>
const video=document.getElementById('v');
const durum=document.getElementById('durum');
let hls=null;let sonIlerleme=Date.now();let oynatmaBasladi=false;let yenidenYukleme=false;
function sayfaYenile(){if(yenidenYukleme)return;yenidenYukleme=true;durum.textContent="Yayin yenileniyor...";setTimeout(function(){location.reload()},1500)}
video.addEventListener('playing',function(){oynatmaBasladi=true;sonIlerleme=Date.now();durum.textContent="Yayin oynatiliyor"});
video.addEventListener('timeupdate',function(){sonIlerleme=Date.now()});
video.addEventListener('waiting',function(){durum.textContent="Yayin bekleniyor..."});
video.addEventListener('error',function(){durum.textContent="Oynatici hatasi, baglanti yenileniyor...";sayfaYenile()});
setInterval(function(){if(oynatmaBasladi&&!video.paused&&!video.ended&&Date.now()-sonIlerleme>30000){sayfaYenile()}},5000);
if(window.Hls&&Hls.isSupported()){
hls=new Hls({enableWorker:true,lowLatencyMode:false,maxBufferLength:30,maxMaxBufferLength:60,backBufferLength:30,liveSyncDurationCount:3,liveMaxLatencyDurationCount:8,maxLiveSyncPlaybackRate:1,maxBufferHole:0.5,manifestLoadingTimeOut:15000,manifestLoadingMaxRetry:8,manifestLoadingRetryDelay:1000,levelLoadingTimeOut:15000,levelLoadingMaxRetry:8,fragLoadingTimeOut:20000,fragLoadingMaxRetry:8,fragLoadingRetryDelay:1000});
hls.loadSource('cam0/index.m3u8');hls.attachMedia(video);
hls.on(Hls.Events.MANIFEST_PARSED,function(){durum.textContent="Yayin bulundu, baslatiliyor...";video.play().catch(function(){})});
hls.on(Hls.Events.ERROR,function(event,data){if(!data.fatal)return;durum.textContent="Baglanti hatasi, kurtarma deneniyor...";if(data.type===Hls.ErrorTypes.NETWORK_ERROR){hls.startLoad()}else if(data.type===Hls.ErrorTypes.MEDIA_ERROR){hls.recoverMediaError()}else{sayfaYenile()}});
}else if(video.canPlayType('application/vnd.apple.mpegurl')){video.src='cam0/index.m3u8';video.addEventListener('loadedmetadata',function(){video.play().catch(function(){})})}else{durum.textContent="Bu tarayici HLS oynatmayi desteklemiyor."}
</script>
</body>
</html>
HTML_EOF

# ==========================================
# OTOMATIK BASLATMA VE DONMA KONTROLU
# ==========================================
RUN cat > /app/start.sh <<'START_EOF'
#!/bin/sh
set -u
mkdir -p /app/live/cam0 /tmp
cp /app/live_index.html /app/live/index.html
YAYIN="http://nexusconnects.org:80/play/live.php?mac=00:1B:79:47:72:00&stream=988851&extension=ts&play_token=i9P5KZaJhe"
USER_AGENT="${USER_AGENT:-Mozilla/5.0}"
REFERER="${REFERER:-}"
ORIGIN="${ORIGIN:-}"
RESET_SURESI=3000
DONMA_SURESI=35
GORUNTU_DONMA_SURESI=60
echo "======================================"
echo "       MIRTI68 CANLI YAYIN"
echo "======================================"
rm -f /tmp/logo1.jpg
curl -fL -k --connect-timeout 10 --max-time 30 --retry 3 -o /tmp/logo1.jpg "https://raw.githubusercontent.com/ipmirti68/Logo/refs/heads/main/IMG-20261018-WA1513.jpg" || echo "[UYARI] Logo indirilemedi"
if ! ffmpeg -v error -i /tmp/logo1.jpg -frames:v 1 -f null - >/dev/null 2>&1; then
echo "[UYARI] Logo yerine siyah logo hazirlaniyor."
ffmpeg -y -v error -f lavfi -i color=c=black:s=120x80 -frames:v 1 /tmp/logo1.jpg
fi
echo "[NGINX] Baslatiliyor..."
nginx
if [ $? -ne 0 ]; then echo "[HATA] NGINX baslatilamadi."; exit 1; fi
BEKLE=2
TUR=1
while true; do
echo ""
echo "======================================"
echo "          TUR $TUR BASLIYOR"
echo "======================================"
rm -f /app/live/cam0/seg_*.ts
rm -f /app/live/cam0/index.m3u8
rm -f /tmp/watch.pgm
BASLANGIC=$(date +%s)
SON_HASH=""
SABIT_SANIYE=0
DURUM="NORMAL"
INPUT_HEADERS=$(printf 'User-Agent: %s\r\n' "$USER_AGENT")
if [ -n "$REFERER" ]; then INPUT_HEADERS="${INPUT_HEADERS}$(printf 'Referer: %s\r\n' "$REFERER"); fi
if [ -n "$ORIGIN" ]; then INPUT_HEADERS="${INPUT_HEADERS}$(printf 'Origin: %s\r\n' "$ORIGIN"); fi
ffmpeg -hide_banner -loglevel warning -fflags +discardcorrupt+genpts -rw_timeout 15000000 -thread_queue_size 1024 -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 -reconnect_on_network_error 1 -headers "$INPUT_HEADERS" -user_agent "$USER_AGENT" -probesize 10M -analyzeduration 10M -i "$YAYIN" -loop 1 -framerate 25 -i /tmp/logo1.jpg -filter_complex "[0:v]fps=25,scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p,split=2[base];[1:v]scale=110:-1[lg];[base][lg]overlay=W-w-35:25:eof_action=pass[v];fps=1,scale=32:18,format=gray[watch]" -map "[v]" -map 0:a? -max_muxing_queue_size 2048 -vsync cfr -af aresample=44100:async=1000 -c:v libx264 -preset ultrafast -tune zerolatency -profile:v main -pix_fmt yuv420p -b:v 550k -maxrate 650k -bufsize 1100k -g 100 -keyint_min 100 -sc_threshold 0 -x264-params "nal-hrd=cbr:force-cfr=1" -c:a aac -b:a 48k -ar 44100 -ac 2 -f hls -hls_time 4 -hls_list_size 8 -hls_delete_threshold 4 -hls_allow_cache 0 -hls_start_number_source epoch -hls_flags delete_segments+independent_segments+program_date_time+temp_file -hls_segment_type mpegts -hls_segment_filename "/app/live/cam0/seg_%d.ts" /app/live/cam0/index.m3u8 -map "[watch]" -an -c:v pgm -update 1 -f image2 /tmp/watch.pgm &
FFPID=$!
echo "[FFMPEG] PID: $FFPID"
while kill -0 "$FFPID" 2>/dev/null; do
sleep 10
SIMDI=$(date +%s)
SON_SEGMENT=0
for DOSYA in /app/live/cam0/seg_*.ts; do [ -f "$DOSYA" ] || continue; ZAMAN=$(stat -c %Y "$DOSYA" 2>/dev/null || echo 0); if [ "$ZAMAN" -gt "$SON_SEGMENT" ]; then SON_SEGMENT=$ZAMAN; fi; done
if [ "$SON_SEGMENT" -eq 0 ]; then GECEN=$((SIMDI - BASLANGIC)); else GECEN=$((SIMDI - SON_SEGMENT)); fi
TOPLAM=$((SIMDI - BASLANGIC))
if [ "$GECEN" -ge "$DONMA_SURESI" ]; then echo "[DONMA] $GECEN saniyedir yeni TS segmenti yok."; DURUM="SEGMENT_DONMASI"; break; fi
if [ -s /tmp/watch.pgm ]; then YENI_HASH=$(cksum /tmp/watch.pgm 2>/dev/null | awk '{print $1}'); if [ -n "$YENI_HASH" ]; then if [ -n "$SON_HASH" ] && [ "$YENI_HASH" = "$SON_HASH" ]; then SABIT_SANIYE=$((SABIT_SANIYE + 10)); else SABIT_SANIYE=0; fi; SON_HASH="$YENI_HASH"; if [ "$SABIT_SANIYE" -ge "$GORUNTU_DONMA_SURESI" ]; then echo "[GORUNTU DONMASI] Goruntu $SABIT_SANIYE saniyedir degismiyor."; DURUM="GORUNTU_DONMASI"; break; fi; fi; fi
if [ "$TOPLAM" -ge "$RESET_SURESI" ]; then echo "[RESET] 150 dakika doldu."; DURUM="ZAMANLI_RESET"; break; fi
echo "[DURUM] Segment: ${GECEN}s | Goruntu sabit: ${SABIT_SANIYE}s"
done
if [ "$DURUM" != "NORMAL" ]; then echo "[FFMPEG] Normal kapatma deneniyor..."; kill -TERM "$FFPID" 2>/dev/null || true; SAYAC=0; while kill -0 "$FFPID" 2>/dev/null && [ "$SAYAC" -lt 5 ]; do sleep 1; SAYAC=$((SAYAC + 1)); done; if kill -0 "$FFPID" 2>/dev/null; then echo "[FFMPEG] Zorla kapatiliyor..."; kill -KILL "$FFPID" 2>/dev/null || true; fi; fi
wait "$FFPID" 2>/dev/null || true
echo "[FFMPEG] Durdu. Sebep: $DURUM"
echo "[BAGLANTI] $BEKLE saniye sonra yeniden denenecek."
sleep "$BEKLE"
if [ "$BEKLE" -lt 16 ]; then BEKLE=$((BEKLE * 2)); else BEKLE=10; fi
TUR=$((TUR + 1))
done
START_EOF

RUN dos2unix /app/start.sh && chmod +x /app/start.sh
EXPOSE 8080
CMD ["/bin/sh", "/app/start.sh"]
