public with sharing class BulkStageTransitionController {

    // Escalated is deliberately absent — it exists specifically to force individual
    // human review, so it's never eligible for bulk treatment as a From Stage.
    private static final Map<String, String> STAGE_TRANSITIONS = new Map<String, String>{
        'Intake' => 'Coverage Confirmed',
        'Coverage Confirmed' => 'Response Ready',
        'Response Ready' => 'Response Submitted',
        'Response Submitted' => 'Negotiation',
        'Negotiation' => 'Agreed',
        'Agreed' => 'Recovery Calculated',
        'Recovery Calculated' => 'Collected',
        'Collected' => 'Closed'
    };

    private static final List<String> FROM_STAGE_ORDER = new List<String>{
        'Intake', 'Coverage Confirmed', 'Response Ready', 'Response Submitted',
        'Negotiation', 'Agreed', 'Recovery Calculated', 'Collected'
    };

    @AuraEnabled(cacheable=true)
    public static List<String> getStageOptions() {
        return FROM_STAGE_ORDER;
    }

    @AuraEnabled(cacheable=true)
    public static Integer previewCount(Id settlementId, String fromStage) {
        return [
            SELECT COUNT()
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c = :fromStage
        ];
    }

    @AuraEnabled
    public static Id enqueueBulkTransition(Id settlementId, String fromStage, String toStage) {
        if (!STAGE_TRANSITIONS.containsKey(fromStage) || STAGE_TRANSITIONS.get(fromStage) != toStage) {
            AuraHandledException ex = new AuraHandledException('Invalid stage transition: ' + fromStage + ' -> ' + toStage);
            ex.setMessage('Invalid stage transition: ' + fromStage + ' -> ' + toStage);
            throw ex;
        }
        return Database.executeBatch(new LienBulkStageTransitionBatch(settlementId, fromStage, toStage), 2000);
    }

    // Not cacheable: this is polled imperatively every few seconds while a batch runs,
    // and a cacheable Apex method can have its response served from the client cache on
    // repeat calls with the same jobId — which would freeze the progress UI on the job's
    // first-seen status instead of reflecting its actual current state.
    @AuraEnabled
    public static BatchJobStatus getJobStatus(Id jobId) {
        List<AsyncApexJob> jobs = [
            SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            AuraHandledException ex = new AuraHandledException('Job not found: ' + jobId);
            ex.setMessage('Job not found: ' + jobId);
            throw ex;
        }
        return new BatchJobStatus(jobs[0]);
    }

    public class BatchJobStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Integer jobItemsProcessed;
        @AuraEnabled public Integer totalJobItems;
        @AuraEnabled public Integer numberOfErrors;

        public BatchJobStatus(AsyncApexJob job) {
            this.status = job.Status;
            this.jobItemsProcessed = job.JobItemsProcessed;
            this.totalJobItems = job.TotalJobItems;
            this.numberOfErrors = job.NumberOfErrors;
        }
    }
}
