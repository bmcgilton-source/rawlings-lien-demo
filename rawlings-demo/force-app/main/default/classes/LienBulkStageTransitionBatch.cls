public with sharing class LienBulkStageTransitionBatch implements Database.Batchable<SObject> {

    private Id settlementId;
    private String fromStage;
    private String toStage;

    public LienBulkStageTransitionBatch(Id settlementId, String fromStage, String toStage) {
        this.settlementId = settlementId;
        this.fromStage = fromStage;
        this.toStage = toStage;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Stage__c
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c = :fromStage
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lien__c> scope) {
        for (Lien__c lien : scope) {
            lien.Stage__c = toStage;
        }
        update scope;
    }

    public void finish(Database.BatchableContext bc) {
    }
}
