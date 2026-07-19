/** Tests pending event-message reply generation and retry behavior. */
@IsTest
private class EventMessageReplyBatchTest {
    private static final String GENERATED_REPLY =
        '素敵な意気込みメッセージをありがとうございます！\nLWCへの挑戦を応援しています 💻✨';

    @IsTest
    static void shouldCompleteMessageWhenGenerationSucceeds() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            // Given
            Test.setMock(HttpCalloutMock.class, new SlackMock());
            EventMessage__c message = TestDataFactory.createEventMessage(
                '開発者',
                'LWCに挑戦したいです',
                true
            );
            EventMessageReplyBatch batch = new EventMessageReplyBatch(
                new FakeReplyGenerator(GENERATED_REPLY, false)
            );

            // When
            Test.startTest();
            batch.execute(null, new List<EventMessage__c>{ message });
            Test.stopTest();

            // Then
            EventMessage__c updatedMessage = [
                SELECT ReplyMessage__c, Status__c
                FROM EventMessage__c
                WHERE Id = :message.Id
            ];
            Assert.areEqual(GENERATED_REPLY, updatedMessage.ReplyMessage__c,
                'The generated Prompt Builder reply should be saved.');
            Assert.areEqual('処理完了', updatedMessage.Status__c,
                'A successfully generated message should be completed.');
        }
    }

    @IsTest
    static void shouldKeepMessagePendingWhenGenerationFails() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            // Given
            Test.setMock(HttpCalloutMock.class, new SlackMock());
            EventMessage__c message = TestDataFactory.createEventMessage(
                '管理者',
                '運用の情報交換を楽しみにしています',
                true
            );
            EventMessageReplyBatch batch = new EventMessageReplyBatch(
                new FakeReplyGenerator(null, true)
            );

            // When
            Test.startTest();
            batch.execute(null, new List<EventMessage__c>{ message });
            Test.stopTest();

            // Then
            EventMessage__c unchangedMessage = [
                SELECT ReplyMessage__c, Status__c
                FROM EventMessage__c
                WHERE Id = :message.Id
            ];
            Assert.isNull(unchangedMessage.ReplyMessage__c,
                'A failed generation should remain available for retry.');
            Assert.areEqual('受付済', unchangedMessage.Status__c,
                'A failed generation should remain pending.');
        }
    }

    @IsTest
    static void shouldDoNothingWhenScopeIsEmpty() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            EventMessageReplyBatch batch = new EventMessageReplyBatch(
                new FakeReplyGenerator(GENERATED_REPLY, false)
            );

            Test.startTest();
            batch.execute(null, new List<EventMessage__c>());
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM EventMessage__c],
                'An empty scope should not create or update records.');
        }
    }

    @IsTest
    static void shouldBuildPendingMessageQueryWhenBatchStarts() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            EventMessageReplyBatch batch = new EventMessageReplyBatch();

            Test.startTest();
            Database.QueryLocator queryLocator = batch.start(null);
            Test.stopTest();

            Assert.isNotNull(queryLocator,
                'The batch should create a query locator for pending event messages.');
        }
    }

    @IsTest
    static void shouldSkipMessageWhenReplyAlreadyExists() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            // Given
            Test.setMock(HttpCalloutMock.class, new SlackMock());
            EventMessage__c message = TestDataFactory.createEventMessage(
                'ユーザー',
                '業務改善のヒントを学びたいです',
                true
            );
            message.ReplyMessage__c = 'Existing reply';
            update message;
            EventMessageReplyBatch batch = new EventMessageReplyBatch(
                new FakeReplyGenerator(GENERATED_REPLY, false)
            );

            // When
            Test.startTest();
            batch.execute(null, new List<EventMessage__c>{ message });
            Test.stopTest();

            // Then
            EventMessage__c unchangedMessage = [
                SELECT ReplyMessage__c, Status__c
                FROM EventMessage__c
                WHERE Id = :message.Id
            ];
            Assert.areEqual('Existing reply', unchangedMessage.ReplyMessage__c,
                'A pre-existing reply should never be overwritten.');
            Assert.areEqual('受付済', unchangedMessage.Status__c,
                'A skipped record should retain its existing status.');
        }
    }

    @IsTest
    static void shouldBuildGroundedRequestWhenRecordIdProvided() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            Test.setMock(HttpCalloutMock.class, new SlackMock());
            Id eventMessageId = TestDataFactory.createEventMessage(
                'その他',
                '多様な参加者と交流したいです',
                true
            ).Id;

            Test.startTest();
            ConnectApi.EinsteinPromptTemplateGenerationsInput request =
                EventMessageReplyBatch.buildPromptRequest(eventMessageId);
            Test.stopTest();

            Assert.isFalse(request.isPreview, 'The request should invoke the LLM, not preview only.');
            Assert.isNotNull(request.additionalConfig,
                'The request should include the Connect API generation configuration.');
            Assert.areEqual('PromptBuilderPreview', request.additionalConfig.applicationName,
                'The application name is required for Prompt Builder generation.');
            Assert.isTrue(request.inputParams.containsKey('Input:EventMessage__c'),
                'The request should use the prompt template event-message input.');
            ConnectApi.WrappedValue wrappedRecord =
                request.inputParams.get('Input:EventMessage__c');
            Map<String, Object> recordReference = (Map<String, Object>) wrappedRecord.value;
            Assert.areEqual(eventMessageId, recordReference.get('id'),
                'The grounding reference should contain the event message Id.');
        }
    }

    /** Replaces the Connect API boundary in unit tests. */
    private class FakeReplyGenerator implements EventMessageReplyBatch.ReplyGenerator {
        private String reply;
        private Boolean shouldFail;

        FakeReplyGenerator(String reply, Boolean shouldFail) {
            this.reply = reply;
            this.shouldFail = shouldFail;
        }

        /**
         * Returns a fixed reply or raises a simulated generation error.
         *
         * @param eventMessageId ignored grounding record identifier
         * @return configured reply text
         */
        public String generateReply(Id eventMessageId) {
            if (shouldFail) {
                throw new FakeGenerationException('Simulated Prompt Builder failure.');
            }
            return reply;
        }
    }

    private class FakeGenerationException extends Exception {
    }

    /** Mocks Slack trigger callouts caused by EventMessage__c inserts. */
    private class SlackMock implements HttpCalloutMock {
        /**
         * Returns a successful Slack response.
         *
         * @param request outbound Slack request
         * @return successful mock response
         */
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(JSON.serialize(new Map<String, Object>{ 'ok' => true }));
            return response;
        }
    }
}
