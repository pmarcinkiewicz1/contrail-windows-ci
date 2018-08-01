#!/bin/bash
set -ex

main()
{
    local index_files
    local test_reports

    test_reports="$1"

    # Output is converted to array by enclosing it in ( and )
    index_files=( $(find "${test_reports}" -name 'Index.html') )
    for f in "${index_files[@]}"; do
        local d

        d=$(dirname "${f}")
        cp "${f}" "${d}/index.html"
    done
}

main "$@"
