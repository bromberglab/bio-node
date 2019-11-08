#!/usr/bin/env sh

# mkdir /output/1/test
# echo $0 > /output/1/test/out.txt
# echo "$@" >> /output/1/test/out.txt
# echo $PREV_ENTRYPOINT >> /output/1/test/out.txt
# echo $PREV_COMMAND >> /output/1/test/out.txt
# echo $INPUTS_META >> /output/1/test/out.txt
# echo $OUTPUTS_META >> /output/1/test/out.txt



# # TODO: Set your configuration here.
# run_executable() {
#     job_in_base="$1"
#     job_out_base="$2"

#     executable="${base_path}/executable"
#     if [ "$(ls -1 "$job_in_base" | wc -l)" -eq 1 ]; then
#         job_in_base="${job_in_base}/$(ls -1 "$job_in_base")"
#     fi

#     "$executable" $args "$job_in_base/${filename}" > "$job_out_base/${filename}"
# }

# # args="$@"
# # base_path="$(pwd)"

# # cd "$input_path"

# # ls -1 | while read id; do
# #     [ -d "${output_path}" ] || mkdir "${output_path}"
# #     [ -d "${output_path}/${id}" ] || mkdir "${output_path}/${id}"
# #     run_executable "${input_path}/${id}" "${output_path}/${id}"
# # done

# # cd "$base_path"


# INPUTS_META='text,stdin,required,filename;text,-i,static,content'
# OUTPUTS_META='file,stdout,out.file;file,-o,out.file'

entrypoint="${PREV_ENTRYPOINT:-}"
command="${PREV_COMMAND:-}"

input_path="${INPUT_PATH:-/input}"
input_path="$(cd "$(dirname "$input_path")"; pwd -P)/$(basename "$input_path")"
output_path="${OUTPUT_PATH:-/output}"
output_path="$(cd "$(dirname "$output_path")"; pwd -P)/$(basename "$output_path")"

inputs_meta="${INPUTS_META:-}"
outputs_meta="${OUTPUTS_META:-}"

save () {
for i do printf %s\\n "$i" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/" ; done
echo " "
}

load() {
    eval "set -- $1"
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

    if [ "$(ls -1 "$job_in_base" | wc -l)" -eq 1 ]
    then
        job_in_base="${job_in_base}/$(ls -1 "$job_in_base")"
    else
        if [ ! "$filename" = "" ]
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
            std_in="< $job_in_base"
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

run_job() {
    job="$1"
    multiple_inputs=false
    [ ! $(count_len ";" "$inputs_meta") -eq 1 ] && multiple_inputs=true
    multiple_outputs=false
    [ ! $(count_len ";" "$outputs_meta") -eq 1 ] && multiple_outputs=true

    cmd="$entrypoint $command"
    std_in=""
    std_in_pre=""
    std_out=""

    for i in $(seq $num_required_inputs)
    do
        input="$(get_input "$required_inputs" $i)"
        run_job_input || return 1
    done
    for i in $(seq $num_optional_inputs)
    do
        input="$(get_input "$optional_inputs" $i)"
        run_job_input || return 1
    done
    for i in $(seq $num_static_inputs)
    do
        input="$(get_input "$static_inputs" $i)"
        run_job_input || return 1
    done

    cmd="$std_in_pre $cmd $std_in"

    >&2 echo eval \'$cmd\'

    return 0
}

run_all_jobs_in() {
    ls -1 "$1" | while read -r job
    do
        run_job "$job" || return 1
    done
}

if [ $(count_len ";" "$inputs_meta") -eq 1 ]
then
    run_all_jobs_in "$input_path" && return 0 || return 1
fi

static_inputs=""
required_inputs=""
optional_inputs=""

get_from_input() {
    input="$1"
    n="$2"

    oIFS="$IFS"
    IFS=","
    set -- $input
    IFS="$oIFS"

    eval echo \${"$n"}
}

get_input() {
    inputs="$1"
    n="$2"

    oIFS="$IFS"
    IFS=";"
    set -- $inputs
    IFS="$oIFS"

    eval echo \${"$n"}
}

addToInput() {
    input="$1"

    oIFS="$IFS"
    IFS=","
    set -- $input
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

oIFS="$IFS"
IFS=";"
set -- $inputs_meta
IFS="$oIFS"
for i in $(seq $(count_len ";" "$inputs_meta"))
do
    addToInput "${i},$(eval echo \${"$i"})"
done

required_inputs="${required_inputs%?}"
optional_inputs="${optional_inputs%?}"
static_inputs="${static_inputs%?}"

num_required_inputs="$(count_len ";" "$required_inputs")"
num_optional_inputs="$(count_len ";" "$optional_inputs")"
num_static_inputs="$(count_len ";" "$static_inputs")"


if [ "$num_required_inputs" -eq 0 ] && [ "$num_optional_inputs" -eq 0 ]
then
    run_all_jobs_in "$input_path/1"
fi


run_job_when_exists() {
    job="$1"

    for j in $(seq $num_required_inputs)
    do
        input="$(get_input "$required_inputs" $i)"
        n=$(get_from_input "$input" 1)
        while [ ! -d "$input_path/$n/$job" ]
        do
            sleep 1
        done
    done

    run_job "$job"
}

for i in $(seq $num_required_inputs)
do
    input="$(get_input "$required_inputs" $i)"
    n=$(get_from_input "$input" 1)
    
    ls -1 "$input_path/$n" | while read -r job
    do
        run_job_when_exists "$job" || return 1
    done
done

for i in $(seq $num_optional_inputs)
do
    input="$(get_input "$optional_inputs" $i)"
    n=$(get_from_input "$input" 1)
    
    ls -1 "$input_path/$n" | while read -r job
    do
        run_job_when_exists "$job" || return 1
    done
done

####

# for i in "${!inputs_meta[@]}"
# do
#     IFS=',' echo "${inputs_meta[i]}" | read -r -a input_meta 
#     if [ ! "${input_meta[2]}" = "static" ]
#     then
#         for j in "${!inputs_meta[@]}"
#     fi
# done

# for i in "${!outputs_meta[@]}"
# do
#     IFS=',' echo "${outputs_meta[i]}" | read -r -a output_meta 
#     output_type="${output_meta[0]}"
#     output_flag="${output_meta[1]}"
#     output_file="${output_meta[2]}"
# done

return 0