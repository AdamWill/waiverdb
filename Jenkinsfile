/*
 * SPDX-License-Identifier: GPL-2.0+
*/

try { // massive try{} catch{} around the entire build for failure notifications
    timestamps {

node('fedora') {
    checkout scm
    stage('Prepare') {
        sh 'sudo dnf -y builddep waiverdb.spec'
        sh 'sudo dnf -y install python3-flake8 python3-pylint python3-pytest python3-sphinx python3-sphinxcontrib-httpdomain'
        /* Needed for mock EPEL7 builds: https://bugzilla.redhat.com/show_bug.cgi?id=1528272 */
        sh 'sudo dnf -y install dnf-utils'
        /* Needed to get the latest /etc/mock/fedora-28-x86_64.cfg */
        sh 'sudo dnf -y update mock-core-configs'
        /* Unit tests need local Postgres */
        sh """
        sudo dnf -y remove postgresql-server || true
        sudo rm -rf /var/lib/pgsql/ || true
        sudo dnf -y install postgresql-server
        sudo postgresql-setup --initdb
        sudo systemctl enable --now postgresql
        sudo -u postgres createuser --superuser $USER
        """
    }
    stage('Invoke Flake8') {
        sh 'flake8'
    }
    stage('Invoke Pylint') {
        sh 'pylint-3 --reports=n waiverdb'
    }
    stage('Run unit tests') {
        sh """
        createdb waiverdb
        cp conf/settings.py.example conf/settings.py
        py.test-3 -v --junitxml=junit-tests.xml tests/
        """
        junit 'junit-tests.xml'
    }
    stage('Build Docs') {
        sh 'make -C docs html'
        archiveArtifacts artifacts: 'docs/_build/html/**'
    }
    /* Can't use GIT_BRANCH because of this issue https://issues.jenkins-ci.org/browse/JENKINS-35230 */
    def git_branch = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
    if (git_branch == 'master') {
        stage('Publish Docs') {
            sshagent (credentials: ['pagure-waiverdb-deploy-key']) {
                sh '''
                mkdir -p ~/.ssh/
                touch ~/.ssh/known_hosts
                ssh-keygen -R pagure.io
                echo 'pagure.io,140.211.169.204 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC198DWs0SQ3DX0ptu+8Wq6wnZMrXUCufN+wdSCtlyhHUeQ3q5B4Hgto1n2FMj752vToCfNTn9mWO7l2rNTrKeBsELpubl2jECHu4LqxkRVihu5UEzejfjiWNDN2jdXbYFY27GW9zymD7Gq3u+T/Mkp4lIcQKRoJaLobBmcVxrLPEEJMKI4AJY31jgxMTnxi7KcR+U5udQrZ3dzCn2BqUdiN5dMgckr4yNPjhl3emJeVJ/uhAJrEsgjzqxAb60smMO5/1By+yF85Wih4TnFtF4LwYYuxgqiNv72Xy4D/MGxCqkO/nH5eRNfcJ+AJFE7727F7Tnbo4xmAjilvRria/+l' >>~/.ssh/known_hosts
                rm -rf docs-on-pagure
                git clone ssh://git@pagure.io/docs/waiverdb.git docs-on-pagure
                rm -r docs-on-pagure/*
                cp -r docs/_build/html/* docs-on-pagure/
                cd docs-on-pagure
                git add -A .
                if [[ "$(git diff --cached --numstat | wc -l)" -eq 0 ]] ; then
                    exit 0 # No changes, nothing to commit
                fi
                git commit -m 'Automatic commit of docs built by Jenkins job ${env.JOB_NAME} #${env.BUILD_NUMBER}'
                git push origin master
                '''
            }
        }
    }
    stage('Build SRPM') {
        sh './rpmbuild.sh -bs'
        archiveArtifacts artifacts: 'rpmbuild-output/**'
    }
    /* We take a flock on the mock configs, to avoid multiple unrelated jobs on
     * the same Jenkins slave trying to use the same mock root at the same
     * time, which will error out. */
    stage('Build RPM') {
        parallel (
            'EPEL7': {
                sh """
                mkdir -p mock-result/el7
                flock /etc/mock/epel-7-x86_64.cfg \
                /usr/bin/mock -v --resultdir=mock-result/el7 -r epel-7-x86_64 --clean --rebuild rpmbuild-output/*.src.rpm
                """
                archiveArtifacts artifacts: 'mock-result/el7/**'
            },
            'F27': {
                sh """
                mkdir -p mock-result/f27
                flock /etc/mock/fedora-27-x86_64.cfg \
                /usr/bin/mock -v --resultdir=mock-result/f27 -r fedora-27-x86_64 --clean --rebuild rpmbuild-output/*.src.rpm
                """
                archiveArtifacts artifacts: 'mock-result/f27/**'
            },
            'F28': {
                sh """
                mkdir -p mock-result/f28
                flock /etc/mock/fedora-28-x86_64.cfg \
                /usr/bin/mock -v --resultdir=mock-result/f28 -r fedora-28-x86_64 --clean --rebuild rpmbuild-output/*.src.rpm
                """
                archiveArtifacts artifacts: 'mock-result/f28/**'
            },
        )
    }
    stage('Invoke Rpmlint') {
        parallel (
            'EPEL7': {
                sh 'rpmlint -f rpmlint-config.py mock-result/el7/*.rpm'
            },
            'F27': {
                sh 'rpmlint -f rpmlint-config.py mock-result/f27/*.rpm'
            },
            'F28': {
                sh 'rpmlint -f rpmlint-config.py mock-result/f28/*.rpm'
            },
        )
    }
}
node('docker') {
    checkout scm
    stage('Build Docker container') {
        unarchive mapping: ['mock-result/f28/': '.']
        def f28_rpm = findFiles(glob: 'mock-result/f28/**/*.noarch.rpm')[0]
        /* XXX: remove this once we divorce waiverdb-cli from waiverdb. */
        def waiverdb_common = findFiles(glob: 'mock-result/f28/**/waiverdb-common-*.noarch.rpm')[0]
        def appversion = sh(returnStdout: true, script: """
            rpm2cpio ${f28_rpm} | \
            cpio --quiet --extract --to-stdout ./usr/lib/python\\*/site-packages/waiverdb\\*.egg-info/PKG-INFO | \
            awk '/^Version: / {print \$2}'
        """).trim()
        /* Git builds will have a version like 0.3.2.dev1+git.3abbb08 following
         * the rules in PEP440. But Docker does not let us have + in the tag
         * name, so let's munge it here. */
        appversion = appversion.replace('+', '-')
        docker.withRegistry(
                'https://docker-registry.engineering.redhat.com/',
                'docker-registry-factory2-builder-sa-credentials') {
            /* Note that the docker.build step has some magic to guess the
             * Dockerfile used, which will break if the build directory (here ".")
             * is not the final argument in the string. */
            def image = docker.build "factory2/waiverdb:internal-${appversion}", "--build-arg waiverdb_rpm=$f28_rpm --build-arg waiverdb_common_rpm=$waiverdb_common --build-arg cacert_url=https://password.corp.redhat.com/RH-IT-Root-CA.crt ."
            image.push()
        }
        docker.withRegistry(
                'https://quay.io/',
                'quay-io-factory2-builder-sa-credentials') {
            def image = docker.build "factory2/waiverdb:${appversion}", "--build-arg waiverdb_rpm=$f28_rpm --build-arg waiverdb_common_rpm=$waiverdb_common ."
            image.push()
        }
        /* Save container version for later steps (this is ugly but I can't find anything better...) */
        writeFile file: 'appversion', text: "${appversion}"
        archiveArtifacts artifacts: 'appversion'
    }
}
node('fedora') {
    sh 'sudo dnf -y install /usr/bin/py.test-3'
    checkout scm
    stage('Perform functional tests') {
        unarchive mapping: ['appversion': 'appversion']
        def appversion = readFile('appversion').trim()
        openshift.withCluster('Upshift') {
            openshift.doAs('upshift-waiverdb-test-jenkins-credentials') {
                openshift.withProject('waiverdb-test') {
                    def template = readYaml file: 'openshift/waiverdb-test-template.yaml'
                    def models = openshift.process(template,
                            '-p', "TEST_ID=${env.BUILD_TAG}",
                            '-p', "WAIVERDB_APP_VERSION=internal-${appversion}")
                    def environment_label = "test-${env.BUILD_TAG}"
                    try {
                        def objects = openshift.create(models)
                        echo "Waiting for pods with label environment=${environment_label} to become Ready"
                        def pods = openshift.selector('pods', ['environment': environment_label])
                        timeout(30) {
                            pods.untilEach(3) {
                                def conds = it.object().status.conditions
                                for (int i = 0; i < conds.size(); i++) {
                                    if (conds[i].type == 'Ready' && conds[i].status == 'True') {
                                        return true
                                    }
                                }
                                return false
                            }
                        }
                        def route_hostname = objects.narrow('route').object().spec.host
                        echo "Running tests against https://${route_hostname}/"
                        def ca_chain = sh(returnStdout: true, script: """openssl s_client \
                                -connect ${route_hostname}:443 \
                                -servername ${route_hostname} -showcerts < /dev/null | \
                              awk 'BEGIN {first_cert=1; in_cert=0};
                                   /BEGIN CERTIFICATE/ { if (first_cert == 1) first_cert = 0; else in_cert = 1 };
                                   { if (in_cert) print };
                                   /END CERTIFICATE/ { in_cert = 0 }'""")
                        writeFile(file: "${env.WORKSPACE}/ca-chain.crt", text: ca_chain)
                        echo "Wrote CA certificate chain to ${env.WORKSPACE}/ca-chain.crt"
                        withEnv(["WAIVERDB_TEST_URL=https://${route_hostname}/",
                                 "REQUESTS_CA_BUNDLE=${env.WORKSPACE}/ca-chain.crt"]) {
                            sh 'py.test-3 -v --junitxml=junit-functional-tests.xml functional-tests/'
                        }
                        junit 'junit-functional-tests.xml'
                    } finally {
                        /* Extract logs for debugging purposes */
                        openshift.selector('deploy,pods', ['environment': environment_label]).logs()
                        /* Tear down everything we just created */
                        openshift.selector('dc,deploy,configmap,secret,svc,route',
                                ['environment': environment_label]).delete()
                    }
                }
            }
        }
    }
}
node('docker') {
    checkout scm
    /* Can't use GIT_BRANCH because of this issue https://issues.jenkins-ci.org/browse/JENKINS-35230 */
    def git_branch = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
    if (git_branch == 'master') {
        stage('Tag "latest".') {
            unarchive mapping: ['appversion': 'appversion']
            def appversion = readFile('appversion').trim()
            docker.withRegistry(
                    'https://docker-registry.engineering.redhat.com/',
                    'docker-registry-factory2-builder-sa-credentials') {
                def image = docker.image("factory2/waiverdb:internal-${appversion}")
                /* Pushes to the internal registry can sometimes randomly fail
                 * with "unknown blob" due to a known issue with the registry
                 * storage configuration. So we retry up to 3 times. */
                retry(3) {
                    image.push('latest')
                }
            }
            docker.withRegistry(
                    'https://quay.io/',
                    'quay-io-factory2-builder-sa-credentials') {
                def image = docker.image("factory2/waiverdb:${appversion}")
                image.push('latest')
            }
        }
    }
}
    }
} catch (e) {
    if (ownership.job.ownershipEnabled) {
        mail to: ownership.job.primaryOwnerEmail,
             cc: ownership.job.secondaryOwnerEmails.join(', '),
             subject: "Jenkins job ${env.JOB_NAME} #${env.BUILD_NUMBER} failed",
             body: "${env.BUILD_URL}\n\n${e}"
    }
    throw e
}
