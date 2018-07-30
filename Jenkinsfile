#!groovy
library "contrailWindows@$BRANCH_NAME"

pipeline {
    agent none

    options {
        timeout time: 5, unit: 'HOURS'
        timestamps()
        lock label: 'testenv_pool', quantity: 1
    }

    stages {
        stage('Preparation') {
            agent { label 'ansible' }
            steps {
                deleteDir()

                // Use the same repo and branch as was used to checkout Jenkinsfile:
                checkout scm

                stash name: "Backups", includes: "backups/**"
                stash name: "CIScripts", includes: "CIScripts/**"
                stash name: "CISelfcheck", includes: "Invoke-Selfcheck.ps1"
                stash name: "StaticAnalysis", includes: "StaticAnalysis/**"
                stash name: "Ansible", includes: "ansible/**"
                stash name: "Monitoring", includes: "monitoring/**"
                stash name: "Flakes", includes: "flakes/**"
            }
        }

        stage('Checkout projects') {
            agent { label 'builder' }
            environment {
                DRIVER_SRC_PATH = "github.com/Juniper/contrail-windows-docker-driver"
            }
            steps {
                deleteDir()
                unstash "CIScripts"
                powershell script: './CIScripts/Checkout.ps1'
                stash name: "SourceCode", excludes: "CIScripts"
            }
        }

        stage('Build, testenv provisioning and sanity checks') {
            parallel {

                stage('CI selfcheck - Windows') {
                    agent { label 'tester' }
                    steps {
                        deleteDir()
                        unstash "Backups"
                        unstash "CIScripts"
                        unstash "CISelfcheck"
                        script {
                            try {
                                powershell script: """./Invoke-Selfcheck.ps1 `
                                    -ReportPath ${env.WORKSPACE}/testReportsRaw/CISelfcheck/raw_NUnit/out.xml"""
                            } finally {
                                stash name: 'CISelfcheckNUnitLogs', includes: 'testReportsRaw/CISelfcheck/raw_NUnit/**', allowEmpty: true
                            }
                        }
                    }
                }

                stage('CI selfcheck - Linux') {
                    when { expression { env.ghprbPullId } }
                    agent { label 'linux' }
                    options {
                        timeout time: 5, unit: 'MINUTES'
                    }
                    steps {
                        deleteDir()
                        unstash "CIScripts"

                        unstash "Monitoring"
                        dir("monitoring") {
                            sh "python3 -m tests.monitoring_tests"
                        }

                        unstash "Flakes"
                        sh "flakes/run-tests.sh"

                        runHelpersTests()
                    }
                }

                stage('Static analysis - Windows') {
                    agent { label 'builder' }
                    steps {
                        deleteDir()
                        unstash "StaticAnalysis"
                        unstash "SourceCode"
                        unstash "CIScripts"
                        unstash "Backups"
                        powershell script: "./StaticAnalysis/Invoke-StaticAnalysisTools.ps1 -RootDir . -Config ${pwd()}/StaticAnalysis"
                    }
                }

                stage('Static analysis - Linux') {
                    when { expression { env.ghprbPullId } }
                    agent { label 'linux' }
                    options {
                        timeout time: 5, unit: 'MINUTES'
                    }
                    steps {
                        deleteDir()

                        unstash "StaticAnalysis"
                        unstash "Ansible"
                        sh "StaticAnalysis/ansible_linter.py"
                    }
                }

                stage('Build') {
                    agent { label 'builder' }
                    environment {
                        THIRD_PARTY_CACHE_PATH = "C:/BUILD_DEPENDENCIES/third_party_cache/"
                        DRIVER_SRC_PATH = "github.com/Juniper/contrail-windows-docker-driver"
                        BUILD_IN_RELEASE_MODE = "false"
                        AGENT_BUILD_THREADS = "6"
                        SIGNTOOL_PATH = "C:/Program Files (x86)/Windows Kits/10/bin/x64/signtool.exe"
                        CERT_PATH = "C:/BUILD_DEPENDENCIES/third_party_cache/common/certs/codilime.com-selfsigned-cert.pfx"
                        CERT_PASSWORD_FILE_PATH = "C:/BUILD_DEPENDENCIES/third_party_cache/common/certs/certp.txt"
                        COMPONENTS_TO_BUILD = "DockerDriver,Extension,Agent"

                        WINCIDEV = credentials('winci-drive')
                    }
                    steps {
                        deleteDir()

                        unstash "CIScripts"
                        unstash "SourceCode"

                        powershell script: './CIScripts/BuildStage.ps1'

                        stash name: "Artifacts", includes: "output/**/*"
                    }
                    post {
                        always {
                            stash name: "sconsTestsLogs", allowEmpty: true, includes: "SconsTestsLogs/**"
                            deleteDir()
                        }
                    }
                }

                stage('Testenv provisioning') {
                    agent { label 'ansible' }
                    when { environment name: "DONT_CREATE_TESTBEDS", value: null }

                    environment {
                        TESTBED = credentials('win-testbed')
                        TESTBED_TEMPLATE = "Template-testbed-201807060237"
                        CONTROLLER_TEMPLATE = "Template-CentOS-7.4-Thin-LinkedClones"
                        TESTENV_MGMT_NETWORK = "VLAN_501_Management"
                        TESTENV_FOLDER = "WINCI/testenvs"
                        VCENTER_DATASTORE_CLUSTER = "WinCI-Datastores-SSD"
                    }

                    steps {
                        script {
                            def testNetwork = getLockedNetworkName()
                            def testEnvName = getTestEnvName(testNetwork)
                            def destroyConfig = [
                                testenv_name: testEnvName,
                                testenv_folder: env.TESTENV_FOLDER
                            ]
                            def deployConfig = [
                                testenv_name: testEnvName,
                                testenv_folder: env.TESTENV_FOLDER,
                                testenv_mgmt_network: env.TESTENV_MGMT_NETWORK,
                                testenv_data_network: testNetwork,
                                testenv_testbed_template: env.TESTBED_TEMPLATE,
                                testenv_controller_template: env.CONTROLLER_TEMPLATE,
                                vcenter_datastore_cluster: env.VCENTER_DATASTORE_CLUSTER,
                            ]

                            deleteDir()
                            unstash 'Ansible'

                            dir('ansible') {
                                // Cleanup testenv before making a new one
                                ansiblePlaybook inventory: 'inventory.testenv',
                                                playbook: 'vmware-destroy-testenv.yml',
                                                extraVars: destroyConfig

                                def testEnvConfPath = "${env.WORKSPACE}/testenv-conf.yaml"
                                def provisioningExtraVars = deployConfig + [
                                    testenv_conf_file: testEnvConfPath
                                ]
                                ansiblePlaybook inventory: 'inventory.testenv',
                                                playbook: 'vmware-deploy-testenv.yml',
                                                extraVars: provisioningExtraVars
                            }

                            stash name: "TestenvConf", includes: "testenv-conf.yaml"
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            agent { label 'tester' }
            when { environment name: "DONT_CREATE_TESTBEDS", value: null }
            steps {
                deleteDir()

                unstash 'CIScripts'
                unstash 'Artifacts'
                unstash 'TestenvConf'

                powershell script: """./CIScripts/Deploy.ps1 `
                    -TestenvConfFile testenv-conf.yaml `
                    -ArtifactsDir output"""
            }
        }

        stage('Test') {
            agent { label 'tester' }
            when { environment name: "DONT_CREATE_TESTBEDS", value: null }
            steps {
                deleteDir()
                unstash 'CIScripts'
                unstash 'TestenvConf'
                script {
                    try {
                        powershell script: """./CIScripts/Test.ps1 `
                            -TestenvConfFile testenv-conf.yaml `
                            -TestReportDir ${env.WORKSPACE}/testReportsRaw/WindowsCompute"""
                    } finally {
                        stash name: 'windowsComputeNUnitLogs', includes: 'testReportsRaw/WindowsCompute/raw_NUnit/**', allowEmpty: true

                        dir('testReportsRaw') {
                            stash name: 'ddriverJUnitLogs', includes:
                            'WindowsCompute/ddriver_junit_test_logs/**', allowEmpty: true

                            stash name: 'detailedLogs', includes:
                            'WindowsCompute/detailed_logs/**', allowEmpty: true
                            }
                        }
                    }
                }
            }
        }

    environment {
        LOG_SERVER = "logs.opencontrail.org"
        LOG_SERVER_USER = "zuul-win"
        LOG_SERVER_FOLDER = "winci"
        LOG_ROOT_DIR = "/var/www/logs"
        MYSQL = credentials('monitoring-mysql')
        MYSQL_HOST = "10.84.12.52"
        MYSQL_DATABASE = "monitoring_test"
    }

    post {
        always {
            node('tester') {
                deleteDir()
                unstash 'CIScripts'
                script {
                    if (tryUnstash('windowsComputeNUnitLogs')) {
                        powershell script: '''./CIScripts/GenerateTestReport.ps1 `
                            -RawNUnitPath testReportsRaw/WindowsCompute/raw_NUnit/report.xml `
                            -OutputDir TestReports/WindowsCompute'''
                    }

                    if (tryUnstash('CISelfcheckNUnitLogs')) {
                        powershell script: '''./CIScripts/GenerateTestReport.ps1 `
                            -RawNUnitPath testReportsRaw/CISelfcheck/raw_NUnit/out.xml `
                            -OutputDir TestReports/CISelfcheck'''
                    }

                    stash name: 'processedTestReports', includes: 'TestReports/**', allowEmpty: true
                }
            }

            node('master') {
                script {
                    deleteDir()
                    def relLogsDstDir = logsRelPathBasedOnTriggerSource(env.JOB_NAME,
                        env.BUILD_NUMBER, env.ZUUL_UUID)

                    def logFilename = 'log.txt.gz'

                    dir('to_publish') {
                        unstash 'processedTestReports'
                        dir('TestReports') {
                            tryUnstash('ddriverJUnitLogs')
                            tryUnstash('detailedLogs')
                            tryUnstash('sconsTestsLogs')
                        }

                        createCompressedLogFile(env.JOB_NAME, env.BUILD_NUMBER, logFilename)

                        def auth = sshAuthority(env.LOG_SERVER_USER, env.LOG_SERVER)
                        def dst = logsDirInFilesystem(env.LOG_ROOT_DIR, env.LOG_SERVER_FOLDER, relLogsDstDir)
                        publishCurrentDirToLogServer(auth, dst)
                    }

                    def fullLogsURL = logsURL(env.LOG_SERVER, env.LOG_SERVER_FOLDER, relLogsDstDir)
                    def logDestMsg = "Full logs URL: ${fullLogsURL}"
                    echo(logDestMsg)
                    if (isGithub()) {
                        sendGithubComment(logDestMsg)
                    }

                    unstash "Flakes"

                    if (containsFlakiness("to_publish/$logFilename")) {
                        echo "Flakiness detected"
                        if (isGithub()) {
                            sendGithubComment("recheck no bug")
                        } else if (env.BRANCH_NAME == "production") {
                            build job: "post-recheck-comment",
                                wait: false,
                                parameters: [
                                    string(name: 'BRANCH_NAME', value: env.BRANCH_NAME),
                                    string(name: 'ZUUL_CHANGE', value: env.ZUUL_CHANGE),
                                    string(name: 'ZUUL_PATCHSET', value: env.ZUUL_PATCHSET),
                                ]
                        }
                    }
                }
            }

            node('ansible') {
                script {
                    deleteDir()
                    def relLogsDstDir = logsRelPathBasedOnTriggerSource(env.JOB_NAME, env.BUILD_NUMBER, env.ZUUL_UUID)
                    def fullLogsURL = logsURL(env.LOG_SERVER, env.LOG_SERVER_FOLDER, relLogsDstDir)

                    unstash "Monitoring"
                    shellCommand('python3', [
                        'monitoring/collect_and_push_build_stats.py',
                        '--job-name', env.JOB_NAME,
                        '--job-status', currentBuild.currentResult,
                        '--build-url', env.BUILD_URL,
                        '--mysql-host', env.MYSQL_HOST,
                        '--mysql-database', env.MYSQL_DATABASE,
                        '--mysql-username', env.MYSQL_USR,
                        '--mysql-password', env.MYSQL_PSW,
                    ] + getReportsLocationParam(fullLogsURL))
                }
            }
        }
    }
}
