#!/bin/bash

set -euo pipefail

# Validate environment variables
: "${UPSTREAM:?Set UPSTREAM using --env}"
: "${UPSTREAM_PORT:?Set UPSTREAM_PORT using --env}"
: "${ERROR_PAGE:?Set ERROR_PAGE using --env}"
: "${CLIENT_MAX_BODY_SIZE:?Set CLIENT_MAX_BODY_SIZE using --env}"
: "${ADMIN_ALLOW:?Set ADMIN_ALLOW using --env}"
: "${ADMIN_DENY:?Set ADMIN_DENY using --env}"
: "${CLIENT_BODY_TIMEOUT:?Set CLIENT_BODY_TIMEOUT using --env}"
: "${CLIENT_HEADER_TIMEOUT:?Set CLIENT_HEADER_TIMEOUT using --env}"
: "${KEEPALIVE_TIMEOUT:?Set KEEPALIVE_TIMEOUT using --env}"
: "${SEND_TIMEOUT:?Set SEND_TIMEOUT using --env}"
PROTOCOL=${PROTOCOL:=HTTP}

# Template an nginx.conf
cat <<EOF >/etc/nginx/nginx.conf
user nginx;
worker_processes 2;

events {
  worker_connections 1024;
}
EOF

if [ "$PROTOCOL" = "HTTP" ]; then

cat <<EOF >/etc/nginx/directory_proxy.conf
proxy_pass http://${UPSTREAM}:${UPSTREAM_PORT};
proxy_set_header Host \$host;
proxy_set_header X-Forwarded-For \$remote_addr;
error_page 403 405 414 416 500 501 502 503 504 ${ERROR_PAGE};
client_max_body_size ${CLIENT_MAX_BODY_SIZE};
client_body_timeout ${CLIENT_BODY_TIMEOUT};
client_header_timeout ${CLIENT_HEADER_TIMEOUT};
keepalive_timeout ${KEEPALIVE_TIMEOUT};
send_timeout ${SEND_TIMEOUT};
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF

cat <<EOF >>/etc/nginx/nginx.conf

http {
  server_tokens off;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;

  server {
    location / {
      include /etc/nginx/directory_proxy.conf;
    }

    location ^~ /admin/ {
      include /etc/nginx/directory_proxy.conf;
      allow ${ADMIN_ALLOW};
      deny ${ADMIN_DENY};
    }

    if ($http_x_forwarded_proto != 'https') {
      return 301 https://\$host\$request_uri;
    }

  }
}
EOF
elif [ "$PROTOCOL" == "TCP" ]; then
cat <<EOF >>/etc/nginx/nginx.conf

stream {
  server {
    listen ${UPSTREAM_PORT};
    proxy_pass ${UPSTREAM}:${UPSTREAM_PORT};
  }
}
EOF
else
echo "Unknown PROTOCOL. Valid values are HTTP or TCP."
fi

echo "Proxy ${PROTOCOL} for ${UPSTREAM}:${UPSTREAM_PORT}"

# Launch nginx in the foreground
/usr/sbin/nginx -g "daemon off;"
