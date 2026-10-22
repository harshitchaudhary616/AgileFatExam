
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
            description: 'Choose a healthy release or the deliberate rollback test.'
        )
    }

    environment {
        IMAGE_NAME = 'gopikaks39/intelligent-traffic-management'
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
                            echo "Dashboard source validation passed."
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
                            echo "Deployment configuration validation passed."
                        '''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -eu

                    if [ "$RELEASE_MODE" = "FAULTY_TEST" ]; then
                        docker build \
                          --build-arg FAULTY_RELEASE=true \
                          -t "$IMAGE_NAME:$BUILD_NUMBER" .
                    else
                        docker build \
                          --build-arg FAULTY_RELEASE=false \
                          -t "$IMAGE_NAME:$BUILD_NUMBER" .
                    fi
                '''
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

                    sleep 3

                    # The dashboard must work in both versions.
                    curl --retry 5 --retry-connrefused --retry-delay 1 \
                      -fsS http://localhost:18081/ >/dev/null

                    if [ "$RELEASE_MODE" = "STABLE" ]; then
                        curl -fsS http://localhost:18081/health
                        echo "Stable image health check passed."
                    else
                        if curl -fsS http://localhost:18081/health; then
                            echo "ERROR: The faulty image unexpectedly passed health checks."
                            exit 1
                        else
                            echo "Expected fault confirmed: /health is unavailable."
                        fi
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
                          -u "$DH_USER" --password-stdin

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
                    withEnv(["KUBECONFIG=${KUBECONFIG_FILE}"]) {
                        sh '''
                            set -eu

                            echo "Deploying image: $IMAGE_NAME:$BUILD_NUMBER"

                            # Substitute the actual image before applying.
                            sed "s|IMAGE_PLACEHOLDER|$IMAGE_NAME:$BUILD_NUMBER|g" \
                              deployment.yaml | kubectl apply -f -

                            if kubectl rollout status \
                              deployment/$DEPLOYMENT_NAME --timeout=60s; then

                                echo "Deployment rollout succeeded."

                            else
                                echo "Rollout failed. Starting automatic rollback."

                                kubectl rollout undo deployment/$DEPLOYMENT_NAME

                                kubectl rollout status \
                                  deployment/$DEPLOYMENT_NAME --timeout=120s

                                echo "Previous deployment restored."

                                if [ "$RELEASE_MODE" = "FAULTY_TEST" ]; then
                                    echo "Expected faulty release rejected; rollback succeeded."
                                else
                                    echo "Unexpected stable deployment failure."
                                    exit 1
                                fi
                            fi

                            echo "Verifying restored deployment."

                            kubectl get deployments
                            kubectl get pods -o wide
                            kubectl get services
                            kubectl rollout history deployment/$DEPLOYMENT_NAME

                            # The previous stable release must serve its health endpoint.
                            curl --retry 10 --retry-connrefused --retry-delay 2 \
                              -fsS http://localhost:30080/health

                            echo "Application health verification passed."
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed. Deployment and recovery checks passed.'
        }
        failure {
            echo 'Pipeline failed. Inspect the first failed stage and console output.'
        }
        always {
            echo 'Traffic management pipeline execution finished.'
        }
    }
}

