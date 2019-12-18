#!/usr/bin/env sh

# INPUTS_META='text,stdin,required,filename;text,-i,static,content'
# OUTPUTS_META='file,stdout,out.file;file,-o,out.file'

random_string()
{
    cat /dev/urandom | base64 | fold -w ${1:-10} | head -n 1 | sed -e 's/[\/\+]/a/g'
}

save () {
    for i do printf %s\\n "$i" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/" ; done
    echo " "
}

load() {
    set -o noglob
    eval "set -- $1"
    set +o noglob
}

count_len() {
    char="$1"
    string="$2"

    echo "${string}" | awk -F"${char}" '{print NF}'
}

run_job_input() {
    n=$(get_from_input "$input" 1) # 1
    type=$(get_from_input "$input" 2) # num_file
    flag=$(get_from_input "$input" 3) # -f
    mode=$(get_from_input "$input" 4) # required
    content=$(get_from_input "$input" 5) # filename | content
    filename=$(get_from_input "$input" 6) # my_file.txt

    is_required=false
    [ "$mode" = "required" ] && is_required=true
    is_static=false
    [ "$mode" = "static" ] && is_static=true

    job_in_base="$input_path"
    if $multiple_inputs
    then
        job_in_base="$input_path/$n"
    fi

    if $is_static
    then
        if [ "$(ls -1 "$job_in_base" | wc -l)" -gt 1 ]
        then
            >&2 echo "Multiple statics not supported."
            return 1
        fi
        if [ "$(ls -1 "$job_in_base" | wc -l)" -eq 0 ]
        then
            return 0
        fi
        job_in_base="${job_in_base}/$(ls -1 "$job_in_base")"
    else
        job_in_base="$job_in_base/$job"
    fi

    if [ ! -d "$job_in_base" ]
    then
        $is_required && (>&2 echo "Required input missing.") && return 1
        return 0
    fi

    if [ "$(ls -1 "$job_in_base" | wc -l)" -eq 1 ] && [ ! "$filename" = "" ]
    then
        job_in_base="${job_in_base}/$(ls -1 "$job_in_base")"
    else
        if [ ! "$filename" = "" ] && [ ! "$filename" = '*' ]
        then
            job_in_base="${job_in_base}/$filename"
        fi
    fi

    if [ "$flag" = "stdin" ]
    then
        if [ ! "$std_in" = "" ] || [ ! "$std_in_pre" = "" ]
        then
            >&2 echo "Multiple stdins not supported."
            return 1
        fi

        if [ "$content" = "filename" ]
        then
            std_in_pre="echo \"$job_in_base\" |"
        else
            std_in="< \"$job_in_base\""
        fi
    else
        if [ "$content" = "content" ]
        then
            cmd="$cmd $flag \"$(cat "$job_in_base")\""
        else
            cmd="$cmd $flag \"$job_in_base\""
        fi
    fi
}

run_job_output() {
    n=$(get_from_output "$output" 1) # 1
    type=$(get_from_output "$output" 2) # out_file
    flag=$(get_from_output "$output" 3) # -o
    filename=$(get_from_output "$output" 4) # my_file.txt

    job_out_base="$output_path"
    if $multiple_outputs
    then
        job_out_base="$output_path/$n"
    fi

    if [ ! -d "$job_out_base" ]
    then
        mkdir "$job_out_base"
    fi

    job_out_base="$job_out_base/$job"

    if [ ! -d "$job_out_base" ]
    then
        mkdir "$job_out_base"
    fi

    if [ "$flag" = "workingdir" ]
    then
        if [ "$filename" = "" ]
        then
            if $has_global_workingdir
            then
                >&2 echo "Multiple workingdir without filename not supported."
                return 1
            fi
            has_global_workingdir=true
        fi
        return 0
    fi

    if [ ! "$filename" = "" ]
    then
        job_out_base="${job_out_base}/$filename"
    fi

    if [ "$flag" = "stdout" ]
    then
        if [ ! "$std_out" = "" ]
        then
            >&2 echo "Multiple stdouts not supported."
            return 1
        fi

        std_out="> \"$job_out_base\""
    else
        cmd="$cmd $flag \"$job_out_base\""
    fi
}

clear_job_output() {
    n=$(get_from_output "$output" 1) # 1
    type=$(get_from_output "$output" 2) # out_file
    flag=$(get_from_output "$output" 3) # -o
    filename=$(get_from_output "$output" 4) # my_file.txt

    job_out_base="$output_path"
    if $multiple_outputs
    then
        job_out_base="$output_path/$n"
    fi

    if [ ! -d "$job_out_base" ]
    then
        return 0
    fi

    job_out_base="$job_out_base/$job"

    if [ ! -d "$job_out_base" ]
    then
        return 0
    fi

    if [ "$flag" = "workingdir" ]
    then
        if [ "$filename" = "" ]
        then
            filter_included_in_list "$previous_files" "$(ls -1A)" | while read i
            do
                mv "$i" "$job_out_base"
            done
        else
            if [ -f "$filename" ] || [ -d "$filename" ]
            then
                mv "$filename" "$job_out_base"
            fi
        fi
    fi

    if [ "$(ls -1 "$job_out_base" | wc -l)" -eq 0 ]
    then
        rm -rf "$job_out_base"
    fi
}

run_job() {
    job="$1"

    k="$(get_k)"
    if [ "$k" -eq 0 ]
    then
        return 0
    fi
    if [ ! "$skip" -eq 0 ]
    then
        skip=$(($skip-1))
        return 0
    fi
    if $multiple_outputs
    then
        current_out="$output_path/1"
    else
        current_out="$output_path"
    fi
    current_out="$current_out/$job"

    [ -d "$current_out" ] && echo Duplicate folder, scheduling broke. && return 1
    mkdir "$current_out"

    k=$(($k-1))
    set_k "$k"
    run_job_checked "$job" || return 1

    return 0
}

included_in_list() {
    line="$1"
    list="$2"
    is_in_list=true

    echo "$list" | while read l
    do
        if [ "$l" = "$line" ]
        then
            return 1
        fi
    done || return 0
    return 1
}

filter_included_in_list() {
    list_a="$1" # shorter
    list_b="$2" # longer

    echo "$list_b" | while read ll
    do
        if ! included_in_list "$ll" "$list_a"
        then
            echo "$ll"
        fi
    done
}

run_job_checked() {
    job="$1"

    cmd="$entrypoint $command"
    std_in=""
    std_in_pre=""
    std_out=""
    has_global_workingdir=false

    for i in $(seq $num_required_inputs)
    do
        input="$(get_input "$required_inputs" $i)"
        run_job_input || return 1
    done || return 1
    for i in $(seq $num_optional_inputs)
    do
        input="$(get_input "$optional_inputs" $i)"
        run_job_input || return 1
    done || return 1
    for i in $(seq $num_static_inputs)
    do
        input="$(get_input "$static_inputs" $i)"
        run_job_input || return 1
    done || return 1
    for i in $(seq $num_outputs)
    do
        output="$(get_output "$outputs_meta" $i)"
        run_job_output || return 1
    done || return 1

    cmd="$std_in_pre $cmd $param $std_in $std_out"

    previous_files="$(ls -1A)"

    echo Running \`$cmd\` ...
    eval "$cmd" || failure=true

    for i in $(seq $num_outputs)
    do
        output="$(get_output "$outputs_meta" $i)"
        clear_job_output || return 1
    done || return 1

    filter_included_in_list "$previous_files" "$(ls -1A)" | while read i
    do
        # clean unneeded created files before next run
        rm -rf "$i"
    done

    if $failure
    then
        return 1
    fi
    return 0
}

run_all_jobs_in() {
    ls -1 "$1" | while read -r job
    do
        run_job "$job" || return 1
    done || return 1

    if [ $(count_len ";" "$inputs_meta") -eq 0 ]
    then
        run_job "job" || return 1
    fi
}

get_from_input() {
    input="$1"
    n="$2"

    oIFS="$IFS"
    IFS=","
    set -o noglob
    set -- $input
    set +o noglob
    IFS="$oIFS"

    eval echo \"\${"$n"}\"
}

get_input() {
    inputs="$1"
    n="$2"

    oIFS="$IFS"
    IFS=";"
    set -o noglob
    set -- $inputs
    set +o noglob
    IFS="$oIFS"

    eval echo \"\${"$n"}\"
}

get_from_output() {
    output="$1"
    n="$2"

    oIFS="$IFS"
    IFS=","
    set -o noglob
    set -- $output
    set +o noglob
    IFS="$oIFS"

    eval echo \"\${"$n"}\"
}

get_output() {
    outputs="$1"
    n="$2"

    oIFS="$IFS"
    IFS=";"
    set -o noglob
    set -- $outputs
    set +o noglob
    IFS="$oIFS"

    eval echo \"\${"$n"}\"
}

addToInput() {
    input="$1"

    oIFS="$IFS"
    IFS=","
    set -o noglob
    set -- $input
    set +o noglob
    IFS="$oIFS"

    type="$4"

    if [ "$type" = "static" ]
    then
        static_inputs="$static_inputs$input;"
    fi
    if [ "$type" = "required" ]
    then
        required_inputs="$required_inputs$input;"
    fi
    if [ "$type" = "optional" ]
    then
        optional_inputs="$optional_inputs$input;"
    fi
}

run_job_when_exists() {
    job="$1"

    for j in $(seq $num_required_inputs)
    do
        input="$(get_input "$required_inputs" $j)"
        n=$(get_from_input "$input" 1)

        retry=0
        while [ ! -d "$input_path/$n/$job" ]
        do
            [ $retry -eq $timeout ] && (>&2 echo "Required Input missing. Timeout.") && return 1
            retry=$(($retry+1))
            sleep 1
        done || return 1
    done || return 1

    run_job "$job" || return 1
    return 0
}

main() {
    failure=false
    entrypoint="${PREV_ENTRYPOINT:-}"
    command="${PREV_COMMAND:-}"
    param="${ADD_PARAMETERS:-}"

    input_path="${INPUT_PATH:-/input}"
    output_path="${OUTPUT_PATH:-/output}"

    [ -d "$input_path" ] || mkdir "$input_path"
    [ -d "$output_path" ] || mkdir "$output_path"

    inputs_meta="${INPUTS_META:-}"
    outputs_meta="${OUTPUTS_META:-}"

    timeout="${TIMEOUT:-30}"

    k="${K:--1}"
    set_k "$k"
    skip="${I:-0}"
    if [ ! $skip -eq 0 ]
    then
        skip=$(($skip*$k))
    fi
    # i ^= skip i jobs

    static_inputs=""
    required_inputs=""
    optional_inputs=""

    oIFS="$IFS"
    IFS=";"
    set -o noglob
    set -- $inputs_meta
    set +o noglob
    IFS="$oIFS"
    for i in $(seq $(count_len ";" "$inputs_meta"))
    do
        addToInput "${i},$(eval echo \${"$i"})"
    done || return 1

    outputs_meta_copy=""
    oIFS="$IFS"
    IFS=";"
    set -o noglob
    set -- $outputs_meta
    set +o noglob
    IFS="$oIFS"
    for i in $(seq $(count_len ";" "$outputs_meta"))
    do
        outputs_meta_copy="$outputs_meta_copy${i},$(eval echo \${"$i"});"
    done || return 1

    required_inputs="${required_inputs%?}"
    optional_inputs="${optional_inputs%?}"
    static_inputs="${static_inputs%?}"
    outputs_meta="${outputs_meta_copy%?}"

    num_required_inputs="$(count_len ";" "$required_inputs")"
    num_optional_inputs="$(count_len ";" "$optional_inputs")"
    num_static_inputs="$(count_len ";" "$static_inputs")"
    num_outputs="$(count_len ";" "$outputs_meta")"

    multiple_inputs=false
    [ ! $(count_len ";" "$inputs_meta") -le 1 ] && multiple_inputs=true
    multiple_outputs=false
    [ ! $(count_len ";" "$outputs_meta") -le 1 ] && multiple_outputs=true

    if ! $multiple_inputs
    then
        run_all_jobs_in "$input_path" && return 0 || return 1
    fi

    # Multiple statics: Just go with the first.
    if [ "$num_required_inputs" -eq 0 ] && [ "$num_optional_inputs" -eq 0 ]
    then
        run_all_jobs_in "$input_path/1"
    fi


    for i in $(seq $num_required_inputs)
    do
        input="$(get_input "$required_inputs" $i)"
        n=$(get_from_input "$input" 1)

        [ -d "$input_path/$n" ] || mkdir "$input_path/$n"
        ls -1 "$input_path/$n" | while read -r job
        do
            run_job_when_exists "$job" || return 1
        done || return 1
    done || return 1

    if [ "$num_required_inputs" -eq 0 ]
    then
        for i in $(seq $num_optional_inputs)
        do
            input="$(get_input "$optional_inputs" $i)"
            n=$(get_from_input "$input" 1)

            [ -d "$input_path/$n" ] || mkdir "$input_path/$n"
            ls -1 "$input_path/$n" | while read -r job
            do
                run_job_when_exists "$job" || return 1
            done || return 1
        done || return 1
    fi
}
rnd_name="$(random_string 20)"
set_k () {
    echo $1 > "/tmp/.k$rnd_name"
}
get_k () {
    cat "/tmp/.k$rnd_name"
}
rm_k () {
    rm "/tmp/.k$rnd_name"
}

main || failure=true
rm_k

if $failure
then
    echo Job failed.
    return 1
fi
