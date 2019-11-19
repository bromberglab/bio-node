FROM alpine:latest

LABEL bio-node="v1.0" \
    output_1="single_file,workingdir,a" \
    output_2="rest_files,workingdir"

RUN echo '#!/usr/bin/env sh' > /app.sh; \
    echo 'touch a' >> /app.sh; \
    echo 'touch b' >> /app.sh; \
    echo 'touch c' >> /app.sh; \
    echo 'sleep 5' >> /app.sh; \
    chmod +x /app.sh

ENTRYPOINT [ "/app.sh" ]
