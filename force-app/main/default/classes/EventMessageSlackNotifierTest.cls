@isTest
private class EventMessageSlackNotifierTest {
    private static final String EXPECTED_CHANNEL_ID = 'C0BEZGCPPSP';

    @isTest
    static void shouldSendSlackNotificationWhenEventMessageInserted() {
        SlackMock mock = new SlackMock(200);
        mock.expectedTextFragment = '【開発者】の方から意気込みが届きました！\n「Headless 360を体験します」';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        insert TestDataFactory.createEventMessage('開発者', 'Headless 360を体験します', false);
        Test.stopTest();
    }

    @isTest
    static void shouldSendOneCombinedSlackNotificationWhenBulkInserted() {
        SlackMock mock = new SlackMock(200);
        mock.expectedTextFragment = 'Bulk enthusiasm 250';
        Test.setMock(HttpCalloutMock.class, mock);
        List<EventMessage__c> messages = TestDataFactory.createEventMessages(251, false);

        Test.startTest();
        new EventMessageSlackNotifier(messages).execute(null);
        Test.stopTest();
    }

    @isTest
    static void shouldSkipCalloutWhenNoMessagesProvided() {
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        new EventMessageSlackNotifier(new List<EventMessage__c>()).execute(null);
        Test.stopTest();
    }

    @isTest
    static void shouldSkipCalloutWhenMessageListIsNull() {
        Test.setMock(HttpCalloutMock.class, new FailingMock());

        Test.startTest();
        new EventMessageSlackNotifier(null).execute(null);
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenSlackReturnsError() {
        Test.setMock(HttpCalloutMock.class, new SlackMock(500));
        List<EventMessage__c> messages = new List<EventMessage__c>{
            TestDataFactory.createEventMessage('管理者', 'エラー経路を確認します', false)
        };

        Test.startTest();
        try {
            new EventMessageSlackNotifier(messages).execute(null);
            Assert.fail('Expected Slack notifier exception for non-success Slack response.');
        } catch (EventMessageSlackNotifier.EventMessageSlackNotifierException error) {
            Assert.isTrue(
                error.getMessage().contains('500'),
                'Exception should include the Slack HTTP status code.'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenSlackReturnsOkFalse() {
        SlackMock mock = new SlackMock(200);
        mock.ok = false;
        mock.errorCode = 'channel_not_found';
        Test.setMock(HttpCalloutMock.class, mock);
        List<EventMessage__c> messages = new List<EventMessage__c>{
            TestDataFactory.createEventMessage('ユーザー', 'Slack API本文のエラーを確認します', false)
        };

        Test.startTest();
        try {
            new EventMessageSlackNotifier(messages).execute(null);
            Assert.fail('Expected Slack notifier exception for Slack ok:false response.');
        } catch (EventMessageSlackNotifier.EventMessageSlackNotifierException error) {
            Assert.isTrue(
                error.getMessage().contains('channel_not_found'),
                'Exception should include the Slack Web API error code.'
            );
        }
        Test.stopTest();
    }

    private class SlackMock implements HttpCalloutMock {
        private Integer statusCode;
        private String expectedTextFragment;
        private Boolean ok;
        private String errorCode;

        SlackMock(Integer statusCode) {
            this.statusCode = statusCode;
            this.ok = statusCode < 300;
            this.errorCode = 'server_error';
        }

        public HttpResponse respond(HttpRequest request) {
            Assert.areEqual(
                'callout:Slack_API/chat.postMessage',
                request.getEndpoint(),
                'Slack request should use the configured named credential endpoint.'
            );
            Assert.areEqual('POST', request.getMethod(), 'Slack request should use POST.');

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            Assert.areEqual(
                EXPECTED_CHANNEL_ID,
                payload.get('channel'),
                'Slack payload should use the custom metadata channel ID.'
            );
            if (!String.isBlank(expectedTextFragment)) {
                Assert.isTrue(
                    String.valueOf(payload.get('text')).contains(expectedTextFragment),
                    'Slack payload should include the expected notification text.'
                );
            }

            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(JSON.serialize(new Map<String, Object>{
                'ok' => ok,
                'error' => errorCode
            }));
            return response;
        }
    }

    private class FailingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            Assert.fail('No HTTP callout should be made for an empty event message list.');
            return new HttpResponse();
        }
    }
}
