public interface IFlowMigrationHandler {
    void run(System.TriggerOperation op, List<SObject> records, Map<Id, SObject> oldMap);
}
