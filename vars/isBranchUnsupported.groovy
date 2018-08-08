def SUPPORTED_BRANCHES = [
    "master"
]

def wasTriggeredByZuul() {
    return env.ZUUL_UUID != null
}

def zuulBranchIsUnsupported() {
    return !SUPPORTED_BRANCHES.contains(env.ZUUL_BRANCH)
}

def call() {
    return wasTriggeredByZuul() && zuulBranchIsUnsupported()
}
