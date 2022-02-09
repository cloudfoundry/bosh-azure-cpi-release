pipeline {
    agent { docker { image 'ruby:3.1.0' } }
    stages {
        stage('rubocop') {
            steps {
                sh 'gem install rubocop'
                sh 'src/bosh_azure_cpi/bin/rubocop_check'
            }
        }
        stage('unit-test') {
            steps {
                sh 'src/bosh_azure_cpi/bin/test-unit -sb'
            }
        }
    }
}