@IsTest
private class GetEventMessageSummaryActionTest {
    @IsTest
    static void shouldReturnChartReadySummaryWhenMessagesExist() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());
        TestDataFactory.createEventMessages(5, true);

        GetEventMessageSummaryAction.Request request = new GetEventMessageSummaryAction.Request();
        request.recentMessageLimit = 3;

        Test.startTest();
        List<GetEventMessageSummaryAction.Response> responses = GetEventMessageSummaryAction.execute(
            new List<GetEventMessageSummaryAction.Request>{ request }
        );
        Test.stopTest();

        Assert.areEqual(1, responses.size(), 'One response should be returned for one request.');
        GetEventMessageSummaryAction.Response response = responses[0];
        Assert.isTrue(response.isSuccess, 'Summary should succeed.');
        Assert.areEqual(5, response.totalCount, 'Total count should include all inserted messages.');
        Assert.isTrue(
            response.slackTextChart.contains('参加者タイプ別 意気込みグラフ'),
            'Slack text chart should include the chart heading.'
        );
        Assert.isTrue(
            response.quickChartUrl.startsWith('https://quickchart.io/chart'),
            'QuickChart URL should be generated when summary data exists.'
        );

        List<Object> roleBreakdown = (List<Object>) JSON.deserializeUntyped(response.roleBreakdownJson);
        Assert.areEqual(3, roleBreakdown.size(), 'Factory data should create three role buckets.');
        Map<String, Object> rolesByName = new Map<String, Object>();
        for (Object roleEntry : roleBreakdown) {
            Map<String, Object> roleValues = (Map<String, Object>) roleEntry;
            rolesByName.put(String.valueOf(roleValues.get('role')), roleValues);
        }
        Map<String, Object> adminRole = (Map<String, Object>) rolesByName.get('管理者');
        Assert.areEqual(2, Integer.valueOf(adminRole.get('count')), 'Administrator bucket should contain two records.');
        Assert.areEqual(
            Decimal.valueOf('40.0'),
            Decimal.valueOf(String.valueOf(adminRole.get('percentage'))),
            'Administrator bucket should be 40 percent.'
        );

        List<Object> recentMessages = (List<Object>) JSON.deserializeUntyped(response.recentMessagesJson);
        Assert.areEqual(3, recentMessages.size(), 'Recent message limit should cap returned messages.');
        Assert.isTrue(
            response.summaryJson.contains('quickChartUrl'),
            'Combined summary JSON should include the image chart URL.'
        );
    }

    @IsTest
    static void shouldReturnEmptySummaryWhenNoMessagesExist() {
        Test.startTest();
        List<GetEventMessageSummaryAction.Response> responses = GetEventMessageSummaryAction.execute(null);
        Test.stopTest();

        Assert.areEqual(1, responses.size(), 'Null request should still return one default response.');
        GetEventMessageSummaryAction.Response response = responses[0];
        Assert.isTrue(response.isSuccess, 'Empty summary should succeed.');
        Assert.areEqual(0, response.totalCount, 'Total count should be zero when no messages exist.');
        Assert.areEqual(null, response.quickChartUrl, 'QuickChart URL should be empty when there is no chart data.');
        Assert.isTrue(
            response.slackTextChart.contains('まだ意気込みは届いていません'),
            'Slack text chart should explain that no messages exist yet.'
        );
    }

    @IsTest
    static void shouldCapRecentMessageLimitAtMaximum() {
        Test.setMock(HttpCalloutMock.class, new SlackMock());
        TestDataFactory.createEventMessages(52, true);

        GetEventMessageSummaryAction.Request request = new GetEventMessageSummaryAction.Request();
        request.recentMessageLimit = 100;

        Test.startTest();
        List<GetEventMessageSummaryAction.Response> responses = GetEventMessageSummaryAction.execute(
            new List<GetEventMessageSummaryAction.Request>{ request }
        );
        Test.stopTest();

        List<Object> recentMessages = (List<Object>) JSON.deserializeUntyped(responses[0].recentMessagesJson);
        Assert.areEqual(50, recentMessages.size(), 'Recent messages should be capped at the maximum limit.');
    }

    /** Mocks Slack trigger callouts caused by EventMessage__c inserts in test setup. */
    private class SlackMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(JSON.serialize(new Map<String, Object>{ 'ok' => true }));
            return response;
        }
    }
}
