// =========================================================================
// OpportunityTrigger
// One trigger per object. Delegates to OpportunityTriggerDispatcher which calls
// every registered handler in order. Add handlers in the dispatcher, never
// here. This file should not change as new Flows are converted.
// =========================================================================
trigger OpportunityTrigger on Opportunity (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    OpportunityTriggerDispatcher.dispatch(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
