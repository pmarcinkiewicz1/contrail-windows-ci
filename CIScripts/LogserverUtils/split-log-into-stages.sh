#!/bin/bash

set -e
set -u
IFS=$'\n'

cd "$(dirname "$1")"

full_log_gz=$(basename "$1")
gunzip --keep "$full_log_gz"
full_log=$(basename "$1" .gz)

function get_stage_regexp() {
    # * Match <Tag> from `<timestamp> | [<Tag>] ...`
    # * Don't count [Pipeline] as a separate tag
    # * Don't count [Directory] in `<timestamp> | [Directory] Running shell script` as separate tag.
    echo '^[^\|]* \| (?:\[Pipeline\] )?\[(?!Pipeline)('"$1"')\](?! Running (?:PowerShell|shell) script$).*$'
}

stage_regexp=$(get_stage_regexp '[\w -]+')

stages=$(perl -lne "s/$stage_regexp/\$1/ or next; print" < "$full_log" | sort --unique)

for stage in $stages
do
    stage_slug=$(echo "$stage" | tr '[:upper:]' '[:lower:]' | tr --squeeze ' ' '-')
    stage_log_filename="log.$stage_slug.txt.gz"
    this_stage_regexp=$(get_stage_regexp "$stage")
    echo "copying '$stage' log to $stage_log_filename"
    grep --perl-regexp "$this_stage_regexp" "$full_log" | gzip > "$stage_log_filename"

    if zgrep "Failed in branch" $stage_log_filename
    then
        mv $stage_log_filename "SUSPECTED-ERROR-HERE-$stage_log_filename"
    fi
done

non_tagged_filename='log.cloning-and-tests-and-post.txt.gz'
echo "copying remaining part of log to $non_tagged_filename"
grep --perl-regexp --invert-match "$stage_regexp" "$full_log" | gzip > "$non_tagged_filename"

echo "creating readme"
cat > README << EOF
The $full_log_gz contains the whole log of the check pipeline.

Log file with SUSPECTED-ERROR-HERE prefix contains logs from failed job stage. Start looking
for errors there.

Additionally, logs from various stages are also available in log.<stage>.txt.gz files.
Most likely, you'd want to check:

* log.build.txt.gz -- contains log of the build
* $non_tagged_filename -- contains info about passed/failed tests (see also TestReports/WindowsCompute directory)
* log.testenv-provisioning.txt.gz -- this is the output from testenv provisioning stage.
  Any failure in this stage is most likely a CI flakiness.

The full documentation on Windows CI logs layout is available here:
https://juniper.github.io/contrail-windows-docs/For%20developers/Interpreting%20CI%20logs/Windows_CI_logs_layout/
EOF

rm "$full_log"
