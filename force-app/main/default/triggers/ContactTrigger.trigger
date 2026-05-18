// =========================================================================
// ContactTrigger
// One trigger per object. Delegates to ContactTriggerDispatcher which calls
// every registered handler in order. Add handlers in the dispatcher, never
// here. This file should not change as new Flows are converted.
// =========================================================================
trigger ContactTrigger on Contact (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    ContactTriggerDispatcher.dispatch(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
