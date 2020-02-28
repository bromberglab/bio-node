#!/bin/sh

debugprintout=false
DOMAIN="${BIONODE_DOMAIN:-https://bio-no.de}"
SYMLINK_DEREF=`[ "${BIONODE_SYMLINK:-0}" -eq 1 ] && echo "h"`

random_string()
{
    cat /dev/urandom | base64 | fold -w ${1:-10} | head -n 1 | sed -e 's/[\/\+]/a/g'
}
SEED="$(random_string)"

safecurltries=5
safecurl() {
    safecurltries=$((safecurltries-1))
    if [ "$safecurltries" -lt 0 ]
    then
        safecurltries=5
        return 1
    fi
    # detect 502
    if ! [ "$(timeout 60 curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/api/.commit/")" = "200" ]
    then
        sleep 10
        safecurl "$@" || return 1
        return 0
    fi
    if timeout 60 curl "$@"
    then
        safecurltries=5
        return 0
    fi
    safecurl "$@" || return 1
}

api() {
    path="$DOMAIN/api/$1/"
    $debugprintout && (echo ">curl $path">&2)
    shift
    safecurl --fail --silent --show-error -b "/tmp/cookies$SEED.txt" "$path" "$@" || return 1
    # $debugprintout && (echo ^curl --fail --silent --show-error -b "/tmp/cookies$SEED.txt" "$path" "$@">&2)
}

apipost() {
    $debugprintout && (echo ">post $2">&2)
    api "$1" -H 'content-type: application/json;charset=UTF-8' --data-binary "$2"
}

sendchunk() {
file="${1:-file}"
chunknum="${2:-1}"
totalchunknum="${3:-1}"
filename="${4:-}"
if [ "$filename" = "" ]
then
    filename="$file"
fi
chunksize="${5:-}"
if [ "$chunksize" = "" ]
then
    chunksize="$(wc -c <"$file" | sed -e 's;[\t ];;g')"
fi
id="${6:-6efa20f1-f706-49e9-bea7-712a1f58ece6/685d784f-316e-4711-919d-be7d7eef075b}"

$debugprintout && echo $chunknum / $totalchunknum [$chunksize]

(printf -- '---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="chunkNumber"\r\n'\
'\r\n'\
"$chunknum"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="chunkSize"\r\n'\
'\r\n'\
"$chunksize"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="currentChunkSize"\r\n'\
'\r\n'\
"$chunksize"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="totalSize"\r\n'\
'\r\n'\
"$filename"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="identifier"\r\n'\
'\r\n'\
"$id"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="filename"\r\n'\
'\r\n'\
"$filename"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="relativePath"\r\n'\
'\r\n'\
"$filename"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="totalChunks"\r\n'\
'\r\n'\
"$totalchunknum"'\r\n'\
'---m4VTH58BqZOtdbg4\r\n'\
'Content-Disposition: form-data; name="file"; filename="'"$filename"'"\r\n'\
'Content-Type: application/octet-stream\r\n'\
'\r\n'; \
cat "$file"; \
printf '\r\n'\
'---m4VTH58BqZOtdbg4--\r\n') | api 'v1/upload' -X PUT -H 'content-type: multipart/form-data; boundary=-m4VTH58BqZOtdbg4' --data-binary @-
}

sendfile() {
    path=$1
    size="${2:-20000000}"

    rm -rf tmp 2>/dev/null
    mkdir tmp
    cd tmp
    if ! [ "$(echo "$path" | cut -c 1)" = "/" ]
    then
        path="../$path"
    fi

    split -b "$size" "$path"

    chunk=0
    totalchunks="$(ls -1 | wc -l | sed -e 's;[\t ];;g')"
    for file in $(ls -1)
    do
        chunk=$((chunk+1))
        echo Send chunk $chunk ...
        sendchunk $file $chunk $totalchunks "$(basename "$path")"
    done

    cd ..
    rm -rf tmp
}

uploadfolder() {
    folder="$1"
    rm "$folder/.DS_Store" 2>/dev/null
    if [ $(find "$folder" -maxdepth 1 -type f | wc -l) -eq 0 ]
    then
        hasfiles="false"
    else
        hasfiles="true"
    fi

    uploadtype="$2"
    uploadname="$3"

    api 'v1/my_upload' -X DELETE
    apipost 'v1/my_upload' '{"file_type":"file","job_count":"auto","name":"'"$uploadname"'"}' >/dev/null

    oldpath="$(pwd)"
    cd "$folder"
    echo Tar ...
    tar cz${SYMLINK_DEREF}f tmp.upload.tar.gz *
    sendfile tmp.upload.tar.gz
    rm tmp.upload.tar.gz
    cd "$oldpath"
    
    sleep 5
    echo Finish ...
    apipost 'v1/finish_upload' '{"extract":true}' >/dev/null
    sleep 1
    while ! [ "$(api 'v1/my_upload' | jq '.reassembling')" = "false" ]
    do
        sleep 3
    done
    while ! [ "$(api 'v1/my_upload' | jq '.extracting')" = "false" ]
    do
        sleep 3
    done
    echo Finalize ...
    apipost 'v1/finalize_upload' '{"manual_format":"'"$uploadtype"'","wrap_files":'"$hasfiles"',"checkboxes":[],"suffixes":[],"types":[]}' >/dev/null
    sleep 5
}

run_template() {
    templatename="$1"

    template="$(safecurl --fail --silent --show-error -b "/tmp/cookies$SEED.txt" -G "$DOMAIN/api/v1/workflow_storage/" --data-urlencode "name=$templatename")"
    if ! [ $? -eq 0 ]
    then
        echo "Could not load template. Is the name wrong?"
        return 1
    fi
    template='{"name":"'"$templatename"'","data":'"$template"'}'
    # template="$(echo "$template" | jq)"
    pk="$(apipost "v1/workflow_run" "$template")"
    echo "Running... ( see $DOMAIN/#/workflows/$pk )"
}

usage() {
    echo "Usage:"
    echo " export TOKEN=<token>"
    echo " $0 <folder> <data-type-name> <data-set-name> [--run-template <template>]"
    echo
    echo "# EXAMPLE:"
    echo "#  $ mkdir -p ./inputs/1/my.job"
    echo "#  $ echo TEST > ./inputs/1/my.job/file1.txt"
    echo "#  $ mkdir -p ./inputs/2/my.job"
    echo "#  $ echo TEST > ./inputs/2/my.job/file2.txt"
    echo "#  $ export TOKEN=sometoken"
    echo "#  $ $0 ./inputs/1 example-data set-1"
    echo "#  $ $0 ./inputs/2 example-data set-2 --run-template example-flow"
}

main() {
    timeout=timeout
    which gtimeout >/dev/null 2>&1 && timeout=gtimeout

    for req in curl jq tar $timeout
    do
        if !(which $req>/dev/null)
        then
            echo Installation of $req required.

            if [ "$req" = "$timeout" ]
            then
                echo "On macOS:"
                echo " $> brew install coreutils"
            fi

            return 1
        fi
    done

    if [ "$#" -lt 3 ] || [ "$1" = "--run-template" ] || [ "$2" = "--run-template" ] || [ "$3" = "--run-template" ]
    then
        usage "$@"
        return 1
    fi

    folder="$1"
    shift
    typename="$1"
    shift
    dataname="$1"
    shift
    runtemplate=false

    if [ "$#" -gt 1 ] && [ "$1" = "--run-template" ]
    then
        runtemplate=true
        templatename="$2"
    fi

    if [ "$(echo ${TOKEN:-} | wc -c)" -lt 2 ]
    then
        echo Token missing!
        echo
        usage "$@"
        return 1
    fi


    echo TOKEN="$(echo $TOKEN | sed -E 's/^(.).*(.)$/\1******\2/')"

    safecurl --fail --silent --show-error -c "/tmp/cookies$SEED.txt" "$DOMAIN/api/token_login/" -H 'content-type: application/json;charset=UTF-8' --data-binary '{"token":"'"$TOKEN"'"}' 2>/dev/null

    auth="$(api 'v1/check_auth' | jq '.authenticated')"
    if ! [ "$auth" = "true" ]
    then
        echo Wrong token.
        return 1
    fi

    if ! [ -d "$folder" ]
    then
        echo Input folder \'"$folder"\' missing.
        return 1
    fi
    uploadfolder "$folder" "$typename" "$dataname"
    $runtemplate && run_template "$templatename"
    rm "/tmp/cookies$SEED.txt"
}

main "$@"
