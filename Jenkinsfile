
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
            description: 'STABLE deploys a healthy version. FAULTY_TEST tests automatic rollback.'
        )
    }

    environment {
        IMAGE_NAME = 'perkeylynx/intelligent-traffic-management'
        DEPLOYMENT_NAME = 'traffic-dashboard'
        CONTAINER_NAME = 'traffic-dashboard'
        SERVICE_NAME = 'traffic-dashboard-service'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'git status --short'
            }
        }

        stage('Parallel Validation') {
            parallel {
                stage('Validate Application') {
                    steps {
                        sh '''
                            set -eu
                            test -s index.html
                            grep -q "Intelligent Traffic Control Center" index.html
                            grep -q "Waiting-Time Alerts" index.html
                            echo "Application validation passed."
                        '''
                    }
                }

                stage('Validate Deployment Files') {
                    steps {
                        sh '''
                            set -eu
                            test -s Dockerfile
                            test -s deployment.yaml
                            test -s Jenkinsfile
                            grep -q "readinessProbe" deployment.yaml
                            grep -q "IMAGE_PLACEHOLDER" deployment.yaml
                            echo "Deployment files validation passed."
                        '''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def mode = params.RELEASE_MODE ?: 'STABLE'
                    env.ACTIVE_RELEASE_MODE = mode

                    if (mode == 'FAULTY_TEST') {
                        sh '''
                            set -eu
                            docker build \
                              --build-arg FAULTY_RELEASE=true \
                              -t "$IMAGE_NAME:$BUILD_NUMBER" .
                        '''
                    } else {
                        sh '''
                            set -eu
                            docker build \
                              --build-arg FAULTY_RELEASE=false \
                              -t "$IMAGE_NAME:$BUILD_NUMBER" .
                        '''
                    }
                }
            }
        }

        stage('Test Docker Image') {
            steps {
                sh '''
                    set -eu

                    TEST_CONTAINER="traffic-test-$BUILD_NUMBER"

                    cleanup() {
                        docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
                    }
                    trap cleanup EXIT

                    docker run -d \
                      --name "$TEST_CONTAINER" \
                      -p 18081:80 \
                      "$IMAGE_NAME:$BUILD_NUMBER"

                    curl --retry 10 \
                      --retry-connrefused \
                      --retry-delay 1 \
                      -fsS http://localhost:18081/ \
                      >/dev/null

                    if [ "$ACTIVE_RELEASE_MODE" = "FAULTY_TEST" ]; then
                        if curl -fsS http://localhost:18081/health; then
                            echo "ERROR: Faulty image unexpectedly passed health check."
                            exit 1
                        else
                            echo "Expected fault confirmed: health endpoint unavailable."
                        fi
                    else
                        curl -fsS http://localhost:18081/health
                        echo "Stable image health test passed."
                    fi
                '''
            }
        }

        stage('Archive Build Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: 'index.html,Dockerfile,Jenkinsfile,deployment.yaml',
                    fingerprint: true
                )
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu

                        echo "$DH_TOKEN" | docker login \
                          --username "$DH_USER" \
                          --password-stdin

                        docker push "$IMAGE_NAME:$BUILD_NUMBER"

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy and Verify Recovery') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'kuberconfig',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    withEnv(["KUBECONFIG=${env.KUBECONFIG_FILE}"]) {
                        script {
                            int rolloutStatus

                            sh '''
                                set -eu

                                sed "s|IMAGE_PLACEHOLDER|$IMAGE_NAME:$BUILD_NUMBER|g" \
                                  deployment.yaml > deployment-rendered.yaml

                                kubectl apply -f deployment-rendered.yaml
                            '''

                            rolloutStatus = sh(
                                script: '''
                                    kubectl rollout status \
                                      deployment/$DEPLOYMENT_NAME \
                                      --timeout=60s
                                ''',
                                returnStatus: true
                            )

                            if (rolloutStatus != 0) {
                                echo 'Deployment rollout failed. Attempting rollback.'

                                def undoStatus = sh(
                                    script: '''
                                        kubectl rollout undo \
                                          deployment/$DEPLOYMENT_NAME
                                    ''',
                                    returnStatus: true
                                )

                                if (undoStatus != 0) {
                                    error('Rollback command failed. Inspect Kubernetes events.')
                                }

                                def recoveryStatus = sh(
                                    script: '''
                                        kubectl rollout status \
                                          deployment/$DEPLOYMENT_NAME \
                                          --timeout=120s
                                    ''',
                                    returnStatus: true
                                )

                                if (recoveryStatus != 0) {
                                    error('Previous deployment did not recover successfully.')
                                }

                                if (env.ACTIVE_RELEASE_MODE != 'FAULTY_TEST') {
                                    error('Unexpected rollout failure in STABLE mode.')
                                }

                                echo 'Faulty release rejected; previous deployment restored.'
                            } else {
                                echo 'Deployment rollout succeeded.'
                            }

                            sh '''
                                set -eu

                                kubectl get deployments
                                kubectl get pods -o wide
                                kubectl get services
                                kubectl rollout history deployment/$DEPLOYMENT_NAME

                                curl --retry 10 \
                                  --retry-connrefused \
                                  --retry-delay 2 \
                                  -fsS http://localhost:30080/health

                                echo "Application health verification passed."
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
            echo 'Pipeline failed. Check the first failed stage and console output.'
        }

        always {
            echo 'Traffic Management pipeline execution finished.'
        }
    }
}
