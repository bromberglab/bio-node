FROM alpine:latest

LABEL bio-node="v1.0" \
    bio-node_entrypoint="/bio-node/entry.sh" \
    input_format="Type Name,Flag,Mode,Filename or Content Mode (see help.bio-no.de/input; remove this line)" \
    input="text,-i,required,filename" \
    output_format="Type Name,Flag,Filename or Content Mode (see help.bio-no.de/output; remove this line)" \
    output="file,stdout,out.filename" \
    ignore_entrypoint="false" \
    ignore_command="true"

# setup bio-node
COPY --from=bromberglab/bio-node /bio-node /bio-node

# set environment variables
WORKDIR /bio-node
ENTRYPOINT [ "/bio-node/entry.sh" ]
CMD [ "--example", "1" ]
