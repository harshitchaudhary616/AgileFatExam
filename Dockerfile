
FROM nginx:alpine

ARG FAULTY_RELEASE=false

COPY index.html /usr/share/nginx/html/index.html

# The readiness endpoint exists in stable releases.
# Faulty test releases intentionally omit it.
RUN if [ "$FAULTY_RELEASE" = "true" ]; then \
      rm -f /usr/share/nginx/html/health; \
    else \
      printf 'ok\n' > /usr/share/nginx/html/health; \
    fi

EXPOSE 80
