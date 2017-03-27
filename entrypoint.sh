#!/bin/bash

set -euo pipefail

# Validate environment variables
: "${SSO_PROXY_DOMAIN:?Set SSO_PROXY_DOMAIN using --env}"
: "${SSO_PROXY_UPSTREAM:?Set SSO_PROXY_UPSTREAM using --env}"
: "${SSO_PROXY_UPSTREAM_PORT:?Set SSO_PROXY_UPSTREAM_PORT using --env}"
: "${SSO_PROFILE_DOMAIN:?Set SSO_PROFILE_DOMAIN using --env}"
: "${SSO_PROFILE_UPSTREAM:?Set SSO_PROFILE_UPSTREAM using --env}"
: "${SSO_PROFILE_UPSTREAM_PORT:?Set SSO_PROFILE_UPSTREAM_PORT using --env}"
: "${ERROR_PAGE:?Set ERROR_PAGE using --env}"
: "${CLIENT_MAX_BODY_SIZE:?Set CLIENT_MAX_BODY_SIZE using --env}"
: "${CLIENT_BODY_TIMEOUT:?Set CLIENT_BODY_TIMEOUT using --env}"
: "${CLIENT_HEADER_TIMEOUT:?Set CLIENT_HEADER_TIMEOUT using --env}"
: "${KEEPALIVE_TIMEOUT:?Set KEEPALIVE_TIMEOUT using --env}"
: "${SEND_TIMEOUT:?Set SEND_TIMEOUT using --env}"
: "${ADMIN_IP_WHITELIST_REGEX:?Set ADMIN_IP_WHITELIST_REGEX using --env}"
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

cat <<EOF >/etc/nginx/sso_common.conf
proxy_set_header Host \$host;
proxy_set_header X-Forwarded-For \$remote_addr;
error_page 403 405 413 414 416 500 501 502 503 504 ${ERROR_PAGE};
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
  client_max_body_size ${CLIENT_MAX_BODY_SIZE};
  client_body_timeout ${CLIENT_BODY_TIMEOUT};
  client_header_timeout ${CLIENT_HEADER_TIMEOUT};
  keepalive_timeout ${KEEPALIVE_TIMEOUT};
  send_timeout ${SEND_TIMEOUT};

  server {
    server_name ${SSO_PROXY_DOMAIN};

    location / {
      proxy_pass http://${SSO_PROXY_UPSTREAM}:${SSO_PROXY_UPSTREAM_PORT};
      include /etc/nginx/sso_common.conf;
    }

    location ^~ /admin/ {
      proxy_pass http://${SSO_PROXY_UPSTREAM}:${SSO_PROXY_UPSTREAM_PORT};
      include /etc/nginx/sso_common.conf;

      set \$allow false;
      if (\$http_x_forwarded_for ~ ${ADMIN_IP_WHITELIST_REGEX}) {
         set \$allow true;
      }
      if (\$allow = false) {
         return 403;
      }
    }

    if (\$http_x_forwarded_proto != 'https') {
      return 301 https://\$host\$request_uri;
    }
  }

  server {
    server_name ${SSO_PROFILE_DOMAIN};

    location / {
      proxy_pass http://${SSO_PROFILE_UPSTREAM}:${SSO_PROFILE_UPSTREAM_PORT};
      include /etc/nginx/sso_common.conf;
    }

    location ^~ /admin/ {
      proxy_pass http://${SSO_PROFILE_UPSTREAM}:${SSO_PROFILE_UPSTREAM_PORT};
      include /etc/nginx/sso_common.conf;

      set \$allow false;
      if (\$http_x_forwarded_for ~ ${ADMIN_IP_WHITELIST_REGEX}) {
         set \$allow true;
      }
      if (\$allow = false) {
         return 403;
      }
    }

    if (\$http_x_forwarded_proto != 'https') {
      return 301 https://\$host\$request_uri;
    }
  }
}
EOF
elif [ "$PROTOCOL" == "TCP" ]; then
cat <<EOF >>nginx.conf

stream {
  server {
    server_name ${SSO_PROXY_DOMAIN};
    listen ${SSO_PROXY_UPSTREAM_PORT};
    proxy_pass ${SSO_PROXY_UPSTREAM}:${SSO_PROXY_UPSTREAM_PORT};
  }

  server {
    server_name ${SSO_PROFILE_DOMAIN};
    listen ${SSO_PROFILE_UPSTREAM_PORT};
    proxy_pass ${SSO_PROFILE_UPSTREAM}:${SSO_PROFILE_UPSTREAM_PORT};
  }
}
EOF
else
echo "Unknown PROTOCOL. Valid values are HTTP or TCP."
fi

echo "Proxy ${PROTOCOL} for ${SSO_PROXY_DOMAIN}:${SSO_PROXY_UPSTREAM_PORT}"
echo "Proxy ${PROTOCOL} for ${SSO_PROFILE_DOMAIN}:${SSO_PROFILE_UPSTREAM_PORT}"


# Launch nginx in the foreground
/usr/sbin/nginx -g "daemon off;"
