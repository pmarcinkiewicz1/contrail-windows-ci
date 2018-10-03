def call(String srcDir, String authority, String destDir) {
    def remoteDir = authority + ":" + destDir
    shellCommand "ssh", [authority, "mkdir", "-p", destDir]
    shellCommand "rsync", ["--prune-empty-dirs", "-r", srcDir + "/", remoteDir]
}
