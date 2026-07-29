public class ClaimantRowError {
    @AuraEnabled public Integer rowNumber;
    @AuraEnabled public String claimantId;
    @AuraEnabled public String claimantName;
    @AuraEnabled public String rejectionCode;
    @AuraEnabled public String rejectionReason;
    public String originalRow;
}
