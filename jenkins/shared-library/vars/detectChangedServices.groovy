// ==============================================================================
// Shared Library: Detect Changed Services
// Returns comma-separated list of services that have changed in this commit
// ==============================================================================

def call() {
    def changedFiles = []
    
    if (env.CHANGE_TARGET) {
        // Pull request - compare against target branch
        changedFiles = sh(
            script: "git diff --name-only origin/${env.CHANGE_TARGET}...HEAD",
            returnStdout: true
        ).trim().split('\n')
    } else {
        // Push to branch - compare against previous commit
        changedFiles = sh(
            script: "git diff --name-only HEAD~1 HEAD",
            returnStdout: true
        ).trim().split('\n')
    }

    def services = [] as Set

    changedFiles.each { file ->
        if (file.startsWith('services/transaction-api/') || file.startsWith('docker/transaction-api')) {
            services.add('transaction-api')
        }
        if (file.startsWith('services/payment-processor/') || file.startsWith('docker/payment-processor')) {
            services.add('payment-processor')
        }
        if (file.startsWith('services/account-service/') || file.startsWith('docker/account-service')) {
            services.add('account-service')
        }
        if (file.startsWith('services/fraud-detection/') || file.startsWith('docker/fraud-detection')) {
            services.add('fraud-detection')
        }
        if (file.startsWith('services/notification-service/') || file.startsWith('docker/notification-service')) {
            services.add('notification-service')
        }
    }

    // If shared code changed, rebuild all
    def sharedChanged = changedFiles.any { 
        it.startsWith('kubernetes/') || it.startsWith('helm/') || it == 'Jenkinsfile' 
    }
    if (sharedChanged || services.isEmpty()) {
        services = ['transaction-api', 'payment-processor', 'account-service', 'fraud-detection', 'notification-service']
    }

    return services.join(',')
}
