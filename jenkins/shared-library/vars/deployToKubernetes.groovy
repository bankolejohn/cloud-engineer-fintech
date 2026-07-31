// ==============================================================================
// Shared Library: Deploy to Kubernetes
// Handles deployment with rollback capability
// ==============================================================================

def call(Map config) {
    def cluster = config.cluster ?: 'gcp-primary'
    def namespace = config.namespace ?: 'finflow'
    def service = config.service
    def imageTag = config.imageTag
    def environment = config.environment ?: 'dev'

    echo "Deploying ${service}:${imageTag} to ${cluster}/${namespace} (${environment})"

    // Get current deployment revision for rollback
    def currentRevision = sh(
        script: "kubectl rollout history deployment/${service} -n ${namespace} --kubeconfig=/tmp/${cluster}-kubeconfig | tail -1 | awk '{print \$1}'",
        returnStdout: true
    ).trim()

    try {
        // Update image
        sh """
            kubectl set image deployment/${service} \
                ${service}=gcr.io/finflow/${service}:${imageTag} \
                -n ${namespace} \
                --kubeconfig=/tmp/${cluster}-kubeconfig
        """

        // Wait for rollout
        sh """
            kubectl rollout status deployment/${service} \
                -n ${namespace} \
                --timeout=300s \
                --kubeconfig=/tmp/${cluster}-kubeconfig
        """

        echo "Deployment successful: ${service}:${imageTag}"

    } catch (Exception e) {
        echo "Deployment failed, rolling back to revision ${currentRevision}"
        
        sh """
            kubectl rollout undo deployment/${service} \
                -n ${namespace} \
                --kubeconfig=/tmp/${cluster}-kubeconfig
        """

        sh """
            kubectl rollout status deployment/${service} \
                -n ${namespace} \
                --timeout=120s \
                --kubeconfig=/tmp/${cluster}-kubeconfig
        """

        error("Deployment of ${service}:${imageTag} failed and was rolled back: ${e.message}")
    }
}
