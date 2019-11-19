FROM alpine:latest

LABEL bio-node="v1.0" \
    bio-node_entrypoint="/bio-node/entry.sh" \
    input="num_file,,required,content" \
    output="num_file,stdout"

RUN echo '#!/usr/bin/env sh' > /app.sh; \
    echo 'echo $(($1+1))' >> /app.sh; \
    echo 'sleep 5' >> /app.sh; \
    chmod +x /app.sh

ENTRYPOINT [ "/app.sh" ]
CMD [ "1" ]
