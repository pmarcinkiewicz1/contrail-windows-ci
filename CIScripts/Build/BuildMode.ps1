function Resolve-BuildMode {
    #Helper function to verify in what build configuration/mode
    #(release/production or debug) Windows compute node components will be built.
    $IsReleaseMode = (Test-Path Env:BUILD_IN_RELEASE_MODE) -and ($Env:BUILD_IN_RELEASE_MODE -ne "0")
    $BuildMode = $(if ($IsReleaseMode) { "production" } else { "debug" })

    return $BuildMode
}
