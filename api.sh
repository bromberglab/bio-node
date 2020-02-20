#!/bin/sh

debugprintout=false
DOMAIN="${BIONODE_DOMAIN:-https://bio-no.de}"
SYMLINK_DEREF=`[[ ! -z ${BIONODE_SYMLINK+x} ]] && [[ "${BIONODE_SYMLINK}" -eq 1 ]] && echo "h"`

random_string()
{
    cat /dev/urandom | base64 | fold -w ${1:-10} | head -n 1 | sed -e 's/[\/\+]/a/g'
}
SEED="$(random_string)"

safecurl() {
    # detect 502
    if ! [ "$(timeout 60 curl -s -o /dev/null -w "%{http_code}" "$DOMAIN/api/.commit/")" = "200" ]
    then
        sleep 10
        safecurl "$@" || return 1
        return 0
    fi
    timeout 60 curl "$@"
}

api() {
    path="$DOMAIN/api/$1/"
    $debugprintout && (echo ">curl $path">&2)
    shift
    safecurl --fail --silent --show-error -b "/tmp/cookies$SEED.txt" "$path" "$@"
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
        sendchunk $file $chunk $totalchunks "$(basename "$path")"
    done

    cd ..
    rm -rf tmp
}

download() {
    downloadtype="$1"
    downloadname="$2"
    outputfile="${3:-}"
    if [ "$outputfile" = "" ]
    then
        outputfile="$(echo "$downloadname.zip" | sed -e 's;/;;g')"
    fi

    url="$(apipost 'v1/create_download' '{"name":"'"$downloadname"'","type":"'"$downloadtype"'"}' | jq -r '.url')"
    safecurl -L --fail --silent --show-error -b "/tmp/cookies$SEED.txt" -o "$outputfile" "$url"
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
    tar cz${SYMLINK_DEREF}f tmp.upload.tar.gz *
    sendfile tmp.upload.tar.gz
    rm tmp.upload.tar.gz
    cd "$oldpath"
    
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
    apipost 'v1/finalize_upload' '{"manual_format":"'"$uploadtype"'","wrap_files":'"$hasfiles"',"checkboxes":[],"suffixes":[],"types":[]}' >/dev/null
}

waitforflow() {
    num="$1"
    sleep 1
    while [ "$(api 'v1/workflows/'"$num" | jq '.finished')" = "false" ]
    do
        sleep 10
    done
}

runapiflow() {
    apiflow="$1"
    inputsdir="$2"
    outputsdir="$3"
    noinputs="${4:-false}"
    mainpath="$(pwd)"

    if ! $noinputs
    then
        if ! [ -d "$inputsdir" ]
        then
            echo "Folder '$inputsdir' does not exist. Exiting."
            return 1
        fi
        if [ "$(ls -1 "$inputsdir" | wc -l)" -eq 0 ]
        then
            echo "Folder '$inputsdir' is empty. Exiting."
            return 1
        fi
    fi

    echo Running flow $apiflow

    if ! $noinputs
    then
        num=0
        cd "$inputsdir"
        for file in $(ls -1)
        do
            num=$((num+1))
            uploadfolder "$file" "$apiflow" "i/$num"
        done
        cd "$mainpath"
    fi
    result="$(apipost 'v1/api_workflow/run' '{"name":"'"$apiflow"'"}')"
    pk="$(echo "$result" | jq -r '.pk')"
    numout="$(echo "$result" | jq -r '.outputs')"

    echo "Running... ( see $DOMAIN/#/workflows/$pk )"
    waitforflow $pk

    rm -rf "$outputsdir" 2>/dev/null
    mkdir "$outputsdir"
    cd "$outputsdir"
    for num in $(seq "$numout")
    do
        download "$apiflow" "o/$num"
    done
    cd "$mainpath"
    echo "Created $numout outputs."
}

usage() {
    echo "Usage:"
    echo " export TOKEN=<token>"
    echo " $0 <api-key> [--no-inputs] [inputs-dir] [outputs-dir]"
    echo
    echo "# WARNING"
    echo "#  Every API key can only be once at a time. Wait for the execution to finish before you run the API again."
    echo "#"
    echo "# If --no-inputs is not set:"
    echo "#  Make sure that the folder 'inputs' exists"
    echo "#  and contains one folder per input of the"
    echo "#  workflow."
    echo "#  The folder outputs will be overriden with"
    echo "#  the results of the workflow."
    echo "#"
    echo "# Default inputs:"
    echo "#  ./inputs"
    echo "# Default outputs:"
    echo "#  ./outputs"
    echo "#"
    echo "# EXAMPLE:"
    echo "#  $ mkdir -p ./inputs/1/my.job"
    echo "#  $ echo TEST > ./inputs/1/my.job/file.txt"
    echo "#  $ export TOKEN=sometoken"
    echo "#  $ $0 someapikey"
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

    if [ "$#" -lt 1 ] || [ "$1" = "--no-inputs" ]
    then
        usage "$@"
        return 1
    fi

    apikey="$1"
    shift
    noinputs="false"
    inputsdir="./inputs"
    outputsdir="./outputs"

    if [ "$#" -gt 0 ] && [ "$1" = "--no-inputs" ]
    then    
        noinputs="true"
        shift
    fi
    if [ "$#" -gt 1 ]
    then
        inputsdir="$1"
        shift
        outputsdir="$1"
        shift
    fi
    if [ "$#" -gt 0 ] && [ "$1" = "--no-inputs" ]
    then
        noinputs="true"
        shift
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

    runapiflow "$apikey" "$inputsdir" "$outputsdir" $noinputs
    rm "/tmp/cookies$SEED.txt"
}

main "$@"
