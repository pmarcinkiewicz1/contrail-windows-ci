def wasTriggeredByZuul() {
    return env.ZUUL_UUID != null
}

def zuulBranchIsUnsupported(ArrayList<String> supportedBranches) {
    return !supportedBranches.contains(env.ZUUL_BRANCH)
}

def call() {
	def SUPPORTED_BRANCHES = [
		"master"
	]

	echo "Zuulv3: SUPPORTED_BRANCHES = " + SUPPORTED_BRANCHES

    return wasTriggeredByZuul() && zuulBranchIsUnsupported(SUPPORTED_BRANCHES)
}
