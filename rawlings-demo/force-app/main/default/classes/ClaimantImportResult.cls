public class ClaimantImportResult {
    @AuraEnabled public Integer rowsReceived = 0;
    @AuraEnabled public Integer createdCount = 0;
    @AuraEnabled public Integer updatedCount = 0;
    @AuraEnabled public Integer rejectedCount = 0;
    @AuraEnabled public Integer automatedCount = 0;
    @AuraEnabled public Integer escalatedCount = 0;
    @AuraEnabled public String rejectionFilename;
    @AuraEnabled public Id rejectionContentDocumentId;
    public List<ClaimantRowError> rowErrors = new List<ClaimantRowError>();
}
