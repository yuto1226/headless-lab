/**
 * Handles EventMessage__c trigger events.
 */
public with sharing class EventMessageTriggerHandler {
    /**
     * Enqueues Slack notification processing after event messages are inserted.
     *
     * @param newMessages inserted event messages
     */
    public static void afterInsert(List<EventMessage__c> newMessages) {
        if (newMessages == null || newMessages.isEmpty()) {
            return;
        }
        System.enqueueJob(new EventMessageSlackNotifier(newMessages));
    }
}
