pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        choice(
            name: 'RELEASE_MODE',
            choices: ['STABLE', 'FAULTY_TEST'],
            description: 'STABLE deploys the working application. FAULTY_TEST tests automatic rollback.'
        )
    }

    environment {
        PATH+DOCKER = '/usr/local/bin'
        IMAGE_NAME = 'perkeylynx/intelligent-traffic-management'
        DEPLOYMENT_NAME = 'traffic-dashboard'
        SERVICE_NAME = 'traffic-dashboard-service'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('Parallel Validation') {
            parallel {
                stage('Validate Application') {
                    steps {
                        sh '''
                            set -eu
                            test -s index.html
                            test -s Dockerfile
                            grep -qi '<html' index.html
                            grep -q 'FROM nginx' Dockerfile
                            echo "Application validation passed."
                        '''
                    }
                }

                stage('Validate Kubernetes Files') {
                    steps {
                        sh '''
                            set -eu
                            test -s deployment.yaml
                            grep -q 'IMAGE_PLACEHOLDER' deployment.yaml
                            grep -q 'kind: Deployment' deployment.yaml
                            grep -q 'kind: Service' deployment.yaml
                            echo "Kubernetes configuration validation passed."
                        '''
                    }
                }
            }
        }

        stage('Verify Docker') {
            steps {
                sh '''
                    set -eu
                    echo "Docker executable:"
                    command -v docker
                    docker --version
                    docker info
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def faulty = params.RELEASE_MODE == 'FAULTY_TEST' ? 'true' : 'false'

                    sh """
                        set -eu
                        /usr/local/bin/docker build \
                            --build-arg FAULTY_RELEASE=${faulty} \
                            -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                    """
                }
            }
        }

        stage('Test Docker Image') {
            steps {
                sh '''
                    set -eu

                    /usr/local/bin/docker rm -f traffic-dashboard-test >/dev/null 2>&1 || true

                    /usr/local/bin/docker run -d \
                        --name traffic-dashboard-test \
                        -p 18081:80 \
                        "${IMAGE_NAME}:${BUILD_NUMBER}"

                    cleanup() {
                        /usr/local/bin/docker rm -f traffic-dashboard-test >/dev/null 2>&1 || true
                    }
                    trap cleanup EXIT

                    sleep 3

                    curl --fail --silent --show-error \
                        http://localhost:18081/ >/dev/null

                    echo "Dashboard HTTP test passed."

                    if [ "$RELEASE_MODE" = "FAULTY_TEST" ]; then
                        if curl --fail --silent \
                            http://localhost:18081/health >/dev/null; then
                            echo "ERROR: Faulty image unexpectedly passed its health check."
                            exit 1
                        fi
                        echo "Expected faulty health-check failure detected."
                    else
                        curl --fail --silent --show-error \
                            http://localhost:18081/health
                        echo "Stable image health check passed."
                    fi
                '''
            }
        }

        stage('Archive Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: 'index.html,Dockerfile,Jenkinsfile,deployment.yaml',
                    allowEmptyArchive: false
                )
            }
        }

        stage('Push Image to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKERHUB_USER',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu

                        echo "$DOCKERHUB_TOKEN" | /usr/local/bin/docker login \
                            --username "$DOCKERHUB_USER" \
                            --password-stdin

                        /usr/local/bin/docker push "${IMAGE_NAME}:${BUILD_NUMBER}"

                        /usr/local/bin/docker logout
                    '''
                }
            }
        }

        stage('Deploy and Verify Kubernetes') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kuberconfig',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    script {
                        withEnv(["KUBECONFIG=${env.KUBECONFIG_FILE}"]) {
                            sh '''
                                set -eu
                                kubectl config current-context

                                sed "s|IMAGE_PLACEHOLDER|${IMAGE_NAME}:${BUILD_NUMBER}|g" \
                                    deployment.yaml > deployment-rendered.yaml

                                kubectl apply -f deployment-rendered.yaml
                            '''

                            int rolloutStatus = sh(
                                script: "kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=120s",
                                returnStatus: true
                            )

                            if (rolloutStatus != 0) {
                                echo 'Deployment rollout failed. Attempting automatic rollback.'

                                int undoStatus = sh(
                                    script: "kubectl rollout undo deployment/${DEPLOYMENT_NAME}",
                                    returnStatus: true
                                )

                                if (undoStatus != 0) {
                                    error('Rollback command failed. Check Kubernetes rollout history.')
                                }

                                int recoveryStatus = sh(
                                    script: "kubectl rollout status deployment/${DEPLOYMENT_NAME} --timeout=120s",
                                    returnStatus: true
                                )

                                if (recoveryStatus != 0) {
                                    error('Rollback was attempted, but the previous deployment did not recover.')
                                }

                                sh '''
                                    kubectl get deployments
                                    kubectl get pods -o wide
                                    kubectl rollout history deployment/traffic-dashboard
                                '''

                                if (params.RELEASE_MODE == 'FAULTY_TEST') {
                                    echo 'FAULTY_TEST passed: failed rollout detected and previous revision restored.'
                                } else {
                                    error('Stable deployment failed; rollback completed. Investigate the cause.')
                                }
                            } else {
                                echo 'Deployment rollout succeeded.'
                            }

                            sh '''
                                kubectl get deployments
                                kubectl get pods -o wide
                                kubectl get services
                                kubectl rollout history deployment/traffic-dashboard
                            '''
                        }
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Review the console output for the failing stage.'
        }

        always {
            sh '''
                /usr/local/bin/docker rm -f traffic-dashboard-test >/dev/null 2>&1 || true
            '''
        }
    }
}
