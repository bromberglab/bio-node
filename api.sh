#!/bin/sh

debugprintout=false

api() {
    path="https://bio-no.de/api/$1/"
    $debugprintout && (echo ">curl $path">&2)
    shift
    curl --fail --silent --show-error -b /tmp/cookies.txt "$path" "$@"
    # $debugprintout && (echo ^curl --fail --silent --show-error -b /tmp/cookies.txt "$path" "$@">&2)
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
    curl -L --fail --silent --show-error -b /tmp/cookies.txt -o "$outputfile" "$url"
}

uploadfolder() {
    folder="$1"
    rm "$folder/.DS_Store" 2>/dev/null
    if [ $(find "$folder" -type f -maxdepth 1 | wc -l) -eq 0 ]
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
    tar czf tmp.upload.tar.gz *
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
        sleep 3
    done
}

runapiflow() {
    apiflow="$1"
    inputsdir="$2"
    outputsdir="$3"
    mainpath="$(pwd)"

    echo Running flow $apiflow

    num=0
    cd "$inputsdir"
    for file in $(ls -1)
    do
        num=$((num+1))
        uploadfolder "$file" "$apiflow" "i/$num"
    done
    cd "$mainpath"
    result="$(apipost 'v1/api_workflow/run' '{"name":"'"$apiflow"'"}')"
    pk="$(echo "$result" | jq -r '.pk')"
    numout="$(echo "$result" | jq -r '.outputs')"

    echo Running...
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

main() {
    for req in curl jq tar
    do
        if !(which $req>/dev/null)
        then
            echo $req required.
            return 1
        fi
    done

    echo TOKEN="$(echo $TOKEN | sed -E 's/^(.).*(.)$/\1******\2/')"

    curl --fail --silent --show-error -c /tmp/cookies.txt 'https://bio-no.de/api/token_login/' -H 'content-type: application/json;charset=UTF-8' --data-binary '{"token":"'"$TOKEN"'"}'
    runapiflow "$1" "inputs" "outputs"
    rm /tmp/cookies.txt
}

main "$@"
