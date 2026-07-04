/**
 * Routes EventMessage__c trigger events to asynchronous handlers.
 */
trigger EventMessageTrigger on EventMessage__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        EventMessageTriggerHandler.afterInsert(Trigger.new);
    }
}
