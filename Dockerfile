# ── Stage 1: Flutter Web 빌드 ──────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

# RANK_API_URL: Railway 빌드 환경변수(Variables > Build)로 주입
ARG RANK_API_URL
RUN flutter build web --release \
    --dart-define=RANK_API_URL=${RANK_API_URL}

# ── Stage 2: Nginx 서빙 ────────────────────────────────────────────
FROM nginx:alpine

# Flutter 빌드 결과물 복사
COPY --from=build /app/build/web /usr/share/nginx/html

# nginx.conf 템플릿 등록
# nginx:alpine 1.19+ 는 컨테이너 시작 시 /etc/nginx/templates/*.template 파일을
# envsubst 처리하여 /etc/nginx/conf.d/ 에 저장
# → Railway가 주입하는 ${PORT} 환경변수가 자동으로 치환됨
COPY --from=build /app/build/web/nginx.conf \
                  /etc/nginx/templates/default.conf.template

# 기본 Nginx 설정 제거 (default.conf 와 충돌 방지)
RUN rm -f /etc/nginx/conf.d/default.conf

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
