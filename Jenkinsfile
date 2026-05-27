pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(
      name: 'RUN_AI_AGENT_REVIEW',
      defaultValue: false,
      description: 'Run advisory AI Agent review after deterministic tests.'
    )
  }

  stages {
    stage('Install Dependencies') {
      steps {
        withPythonEnv('python3') {
          sh 'python -m pip install --upgrade pip'
          sh 'python -m pip install -r requirements-dev.txt'
        }
      }
    }

    stage('Python Unit Tests') {
      steps {
        withPythonEnv('python3') {
          sh 'bash tests/python/run-tests.sh'
        }
      }
    }

    stage('Shell Contract Tests') {
      steps {
        withPythonEnv('python3') {
          sh 'bash tests/shell/run-tests.sh'
        }
      }
    }

    stage('Robot Acceptance Tests') {
      steps {
        withPythonEnv('python3') {
          sh 'bash tests/robot/run-tests.sh'
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'test-results/robot/**', allowEmptyArchive: true
          junit allowEmptyResults: true, testResults: 'test-results/robot/xunit.xml'
        }
      }
    }

    stage('AI Agent Advisory Review') {
      when {
        expression { return params.RUN_AI_AGENT_REVIEW }
      }
      steps {
        aiAgent(
          agent: codex(),
          prompt: 'Review this Jenkins build workspace. Summarize failing tests, identify likely root causes, and propose non-mutating next actions. Do not modify files or access external infrastructure.',
          requireApprovals: true,
          approvalTimeoutSeconds: 300
        )
      }
    }
  }
}
