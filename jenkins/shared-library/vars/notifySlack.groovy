// ==============================================================================
// Shared Library: Slack Notification
// Sends formatted deployment notifications to Slack
// ==============================================================================

def call(Map config) {
    def status = config.status ?: 'INFO'
    def message = config.message ?: ''
    def channel = config.channel ?: '#finflow-deployments'
    
    def color = 'warning'
    def emoji = ':information_source:'
    
    switch(status) {
        case 'SUCCESS':
            color = 'good'
            emoji = ':white_check_mark:'
            break
        case 'FAILURE':
            color = 'danger'
            emoji = ':x:'
            break
        case 'STARTED':
            color = '#439FE0'
            emoji = ':rocket:'
            break
        case 'ROLLBACK':
            color = 'danger'
            emoji = ':rewind:'
            break
    }

    def payload = [
        channel: channel,
        color: color,
        message: "${emoji} *${status}*: ${message}\n" +
                 "Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}\n" +
                 "Branch: ${env.BRANCH_NAME}\n" +
                 "Commit: ${env.GIT_COMMIT_SHORT}\n" +
                 "<${env.BUILD_URL}|View Build>"
    ]

    slackSend(payload)
}
