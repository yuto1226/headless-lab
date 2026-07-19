/**
 * Generates Prompt Builder replies for pending event messages.
 * Run this batch with a scope size of one because each record invokes the LLM.
 */
public with sharing class EventMessageReplyBatch implements
    Database.Batchable<SObject>,
    Database.AllowsCallouts,
    Database.Stateful {
    private static final String PROMPT_TEMPLATE_API_NAME = 'Event_Message_Gold_Reply';
    private static final String PROMPT_INPUT_API_NAME = 'Input:EventMessage__c';
    private static final String PROMPT_APPLICATION_NAME = 'PromptBuilderPreview';
    private static final String STATUS_RECEIVED = '受付済';
    private static final String STATUS_COMPLETED = '処理完了';

    private ReplyGenerator replyGenerator;
    private Integer processedCount = 0;
    private Integer failedCount = 0;

    /** Creates a batch that invokes the configured Prompt Builder template. */
    public EventMessageReplyBatch() {
        this.replyGenerator = new PromptBuilderReplyGenerator();
    }

    /**
     * Supplies a replaceable generation boundary for isolated unit tests.
     *
     * @param replyGenerator generator used for each event message
     */
    @TestVisible
    private EventMessageReplyBatch(ReplyGenerator replyGenerator) {
        if (replyGenerator == null) {
            throw new EventMessageReplyBatchException('A reply generator is required.');
        }
        this.replyGenerator = replyGenerator;
    }

    /**
     * Selects event messages that have not yet received an AI reply.
     *
     * @param context current batch context
     * @return query locator for pending event messages
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, AttendeeRole__c, Enthusiasm__c, ReplyMessage__c
            FROM EventMessage__c
            WHERE Status__c = :STATUS_RECEIVED
            WITH USER_MODE
        ]);
    }

    /**
     * Generates and saves replies for the current scope.
     * The MCP controller always starts this batch with a scope size of one.
     *
     * @param context current batch context
     * @param scope event messages in the current scope
     */
    public void execute(Database.BatchableContext context, List<EventMessage__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        List<EventMessage__c> messagesToUpdate = new List<EventMessage__c>();
        for (EventMessage__c message : scope) {
            // ReplyMessage__c is a long-text field and cannot be filtered in SOQL.
            if (String.isNotBlank(message.ReplyMessage__c)) {
                continue;
            }
            try {
                String reply = replyGenerator.generateReply(message.Id);
                if (String.isBlank(reply)) {
                    throw new EventMessageReplyBatchException('Prompt Builder returned an empty reply.');
                }
                messagesToUpdate.add(new EventMessage__c(
                    Id = message.Id,
                    ReplyMessage__c = reply,
                    Status__c = STATUS_COMPLETED
                ));
            } catch (Exception generationError) {
                // Keep the record pending so a later batch can retry it.
                failedCount++;
            }
        }

        if (messagesToUpdate.isEmpty()) {
            return;
        }

        List<Database.SaveResult> saveResults = Database.update(
            messagesToUpdate,
            false,
            AccessLevel.USER_MODE
        );
        trackSaveResults(saveResults);
    }

    /**
     * Logs a non-sensitive completion summary. Replace this with the project's
     * administrator notification service when one is available.
     *
     * @param context completed batch context
     */
    @SuppressWarnings('PMD.AvoidDebugStatements')
    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, String.format(
            'EventMessageReplyBatch completed. Processed: {0}, Failed: {1}',
            new List<Object>{ processedCount, failedCount }
        ));
    }

    /**
     * Records partial-success DML outcomes without exposing message content.
     *
     * @param saveResults results returned by the user-mode update
     */
    private void trackSaveResults(List<Database.SaveResult> saveResults) {
        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                processedCount++;
            } else {
                failedCount++;
            }
        }
    }

    /**
     * Builds the Prompt Builder input using the event message as grounding data.
     *
     * @param eventMessageId event message used as prompt grounding data
     * @return configured Prompt Builder generation request
     */
    @TestVisible
    private static ConnectApi.EinsteinPromptTemplateGenerationsInput buildPromptRequest(
        Id eventMessageId
    ) {
        Map<String, Object> recordReference = new Map<String, Object>{
            'id' => eventMessageId
        };
        ConnectApi.WrappedValue recordValue = new ConnectApi.WrappedValue();
        recordValue.value = recordReference;

        ConnectApi.EinsteinPromptTemplateGenerationsInput request =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        request.isPreview = false;
        // Connect API requires an application name to resolve and generate the prompt.
        request.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        request.additionalConfig.applicationName = PROMPT_APPLICATION_NAME;
        request.inputParams = new Map<String, ConnectApi.WrappedValue>{
            PROMPT_INPUT_API_NAME => recordValue
        };
        return request;
    }

    /** Boundary for Prompt Builder generation. */
    @TestVisible
    private interface ReplyGenerator {
        /**
         * Generates one reply for an event message.
         *
         * @param eventMessageId event message used as prompt grounding data
         * @return generated reply text
         */
        String generateReply(Id eventMessageId);
    }

    /** Production implementation of the Prompt Builder generation boundary. */
    private class PromptBuilderReplyGenerator implements ReplyGenerator {
        /**
         * Invokes the configured Prompt Builder template.
         *
         * @param eventMessageId event message used as prompt grounding data
         * @return generated reply text
         */
        public String generateReply(Id eventMessageId) {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    PROMPT_TEMPLATE_API_NAME,
                    buildPromptRequest(eventMessageId)
                );

            if (result == null || result.generations == null || result.generations.isEmpty()) {
                throw new EventMessageReplyBatchException('Prompt Builder returned no generations.');
            }
            return result.generations[0].text;
        }
    }

    /** Raised when reply generation cannot produce an updateable message. */
    public class EventMessageReplyBatchException extends Exception {
    }
}
