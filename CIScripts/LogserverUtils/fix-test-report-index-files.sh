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
        # NOTE: We have to preserve two index files, because:
        #       - `Index.html` is referenced in other html files
        #       - `index.html` can be loaded by default when entering `pretty_test_report`
        cp "${f}" "${d}/index.html"
    done
}

main "$@"
