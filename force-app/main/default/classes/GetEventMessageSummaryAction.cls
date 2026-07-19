/**
 * Summarizes event-message enthusiasm records for Headless360Bot and MCP clients.
 */
global with sharing class GetEventMessageSummaryAction {
    private static final Integer DEFAULT_RECENT_LIMIT = 10;
    private static final Integer MAX_RECENT_LIMIT = 50;
    private static final Integer BAR_WIDTH = 10;
    private static final String UNKNOWN_ROLE = '未指定';
    private static final String QUICKCHART_BASE_URL = 'https://quickchart.io/chart';

    private static final Map<String, RoleStyle> ROLE_STYLES_BY_ROLE = new Map<String, RoleStyle>{
        '管理者' => new RoleStyle('🛠️', '#2F80ED'),
        'ユーザー' => new RoleStyle('🌟', '#27AE60'),
        '開発者' => new RoleStyle('💻', '#9B51E0'),
        'その他' => new RoleStyle('🎈', '#F2994A'),
        UNKNOWN_ROLE => new RoleStyle('🐾', '#828282')
    };

    /**
     * Returns aggregated participant-role counts and chart-ready JSON for Slack responses.
     *
     * @param requests summary options from Flow, Agentforce, or Hosted MCP clients
     * @return one summary response per request
     */
    @InvocableMethod(
        label='イベントメッセージ投稿を集計'
        description='EventMessage__c を参加者種別ごとに集計します。必須入力はありません。recentMessageLimit が未指定の場合は最新10件、最大50件を返します。'
        category='Headless360Bot'
    )
    global static List<Response> execute(List<Request> requests) {
        List<Request> safeRequests = requests == null || requests.isEmpty()
            ? new List<Request>{ new Request() }
            : requests;

        ensureReadAccess();

        SummaryData summary = loadSummary();
        List<Response> responses = new List<Response>();
        for (Request request : safeRequests) {
            responses.add(buildResponse(summary, getRecentLimit(request)));
        }
        return responses;
    }

    /** Ensures the caller can read the object and fields used by the MCP summary. */
    private static void ensureReadAccess() {
        if (!Schema.sObjectType.EventMessage__c.isAccessible()
            || !EventMessage__c.AttendeeRole__c.getDescribe().isAccessible()
            || !EventMessage__c.Enthusiasm__c.getDescribe().isAccessible()
            || !EventMessage__c.ReplyMessage__c.getDescribe().isAccessible()
            || !EventMessage__c.Status__c.getDescribe().isAccessible()
            || !EventMessage__c.CreatedDate.getDescribe().isAccessible()) {
            throw new EventMessageSummaryException('Event message read access is required.');
        }
    }

    /** Loads all aggregate and recent-message data in two bounded queries. */
    private static SummaryData loadSummary() {
        SummaryData summary = new SummaryData();

        for (AggregateResult result : [
            SELECT AttendeeRole__c role, COUNT(Id) countValue
            FROM EventMessage__c
            WITH USER_MODE
            GROUP BY AttendeeRole__c
            ORDER BY AttendeeRole__c ASC NULLS LAST
        ]) {
            String role = normalizeRole((String) result.get('role'));
            Integer countValue = Integer.valueOf(result.get('countValue'));
            summary.totalCount += countValue;
            summary.roleCounts.put(role, countValue);
        }

        summary.recentMessages = [
            SELECT Id, AttendeeRole__c, Enthusiasm__c, ReplyMessage__c, Status__c, CreatedDate
            FROM EventMessage__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_RECENT_LIMIT
        ];

        return summary;
    }

    /** Builds one invocable response from the shared summary data. */
    private static Response buildResponse(SummaryData summary, Integer recentLimit) {
        Response response = new Response();
        response.isSuccess = true;
        response.totalCount = summary.totalCount;
        response.roleBreakdownJson = buildRoleBreakdownJson(summary);
        response.recentMessagesJson = buildRecentMessagesJson(summary.recentMessages, recentLimit);
        response.slackTextChart = buildSlackTextChart(summary);
        response.quickChartUrl = buildQuickChartUrl(summary);
        response.summaryJson = buildSummaryJson(response);
        return response;
    }

    /** Serializes the role breakdown in a chart-friendly shape for the LLM. */
    private static String buildRoleBreakdownJson(SummaryData summary) {
        List<RoleBreakdown> breakdown = new List<RoleBreakdown>();
        for (String role : getSortedRoles(summary.roleCounts)) {
            Integer countValue = summary.roleCounts.get(role);
            RoleStyle style = getRoleStyle(role);
            RoleBreakdown item = new RoleBreakdown();
            item.role = role;
            item.count = countValue;
            item.percentage = calculatePercentage(countValue, summary.totalCount);
            item.emoji = style.emoji;
            item.color = style.color;
            item.textBar = buildBar(item.percentage);
            breakdown.add(item);
        }
        return JSON.serialize(breakdown);
    }

    /** Serializes recent messages so the LLM can quote or summarize enthusiasm safely. */
    private static String buildRecentMessagesJson(List<EventMessage__c> recentMessages, Integer recentLimit) {
        List<RecentMessage> messages = new List<RecentMessage>();
        Integer cappedLimit = Math.min(recentLimit, recentMessages.size());
        for (Integer index = 0; index < cappedLimit; index++) {
            EventMessage__c source = recentMessages[index];
            RecentMessage message = new RecentMessage();
            message.id = source.Id;
            message.role = normalizeRole(source.AttendeeRole__c);
            message.enthusiasm = source.Enthusiasm__c;
            message.replyMessage = source.ReplyMessage__c;
            message.status = source.Status__c;
            message.createdDate = source.CreatedDate;
            messages.add(message);
        }
        return JSON.serialize(messages);
    }

    /** Creates the Slack-native text bar chart used when image rendering is unavailable. */
    private static String buildSlackTextChart(SummaryData summary) {
        if (summary.totalCount == 0) {
            return 'まだ意気込みは届いていません。最初の一言を待っています 🐾';
        }

        List<String> lines = new List<String>{ '*参加者タイプ別 意気込みグラフ*' };
        for (String role : getSortedRoles(summary.roleCounts)) {
            Integer countValue = summary.roleCounts.get(role);
            Decimal percentage = calculatePercentage(countValue, summary.totalCount);
            RoleStyle style = getRoleStyle(role);
            lines.add(String.format(
                '{0} {1} {2} {3}% ({4}件)',
                new List<String>{
                    style.emoji,
                    role,
                    buildBar(percentage),
                    formatDecimal(percentage),
                    String.valueOf(countValue)
                }
            ));
        }
        lines.add('小さな意気込みが、会場をぽんっと盛り上げています。');
        return String.join(lines, '\n');
    }

    /** Creates a public QuickChart URL for Slack Block Kit image blocks. */
    private static String buildQuickChartUrl(SummaryData summary) {
        if (summary.totalCount == 0) {
            return null;
        }

        List<String> labels = new List<String>();
        List<Integer> values = new List<Integer>();
        List<String> colors = new List<String>();
        for (String role : getSortedRoles(summary.roleCounts)) {
            labels.add(role);
            values.add(summary.roleCounts.get(role));
            colors.add(getRoleStyle(role).color);
        }

        Map<String, Object> dataset = new Map<String, Object>{
            'data' => values,
            'backgroundColor' => colors
        };
        Map<String, Object> config = new Map<String, Object>{
            'type' => 'doughnut',
            'data' => new Map<String, Object>{
                'labels' => labels,
                'datasets' => new List<Object>{ dataset }
            },
            'options' => new Map<String, Object>{
                'plugins' => new Map<String, Object>{
                    'legend' => new Map<String, Object>{ 'position' => 'right' },
                    'title' => new Map<String, Object>{
                        'display' => true,
                        'text' => '参加者タイプ別 意気込み'
                    }
                }
            }
        };

        return QUICKCHART_BASE_URL + '?width=720&height=420&backgroundColor=white&c='
            + EncodingUtil.urlEncode(JSON.serialize(config), 'UTF-8');
    }

    /** Serializes the complete response for clients that prefer one JSON payload. */
    private static String buildSummaryJson(Response response) {
        Map<String, Object> payload = new Map<String, Object>{
            'totalCount' => response.totalCount,
            'roleBreakdown' => JSON.deserializeUntyped(response.roleBreakdownJson),
            'recentMessages' => JSON.deserializeUntyped(response.recentMessagesJson),
            'slackTextChart' => response.slackTextChart,
            'quickChartUrl' => response.quickChartUrl
        };
        return JSON.serialize(payload);
    }

    /** Returns a bounded recent-message limit from the request. */
    private static Integer getRecentLimit(Request request) {
        if (request == null || request.recentMessageLimit == null || request.recentMessageLimit < 1) {
            return DEFAULT_RECENT_LIMIT;
        }
        return Math.min(request.recentMessageLimit, MAX_RECENT_LIMIT);
    }

    /** Normalizes blank participant roles into a stable bucket. */
    private static String normalizeRole(String role) {
        return String.isBlank(role) ? UNKNOWN_ROLE : role.trim();
    }

    /** Returns roles sorted by count descending, then label ascending. */
    private static List<String> getSortedRoles(Map<String, Integer> roleCounts) {
        List<RoleSortItem> sortItems = new List<RoleSortItem>();
        for (String role : roleCounts.keySet()) {
            sortItems.add(new RoleSortItem(role, roleCounts.get(role)));
        }
        sortItems.sort();

        List<String> roles = new List<String>();
        for (RoleSortItem item : sortItems) {
            roles.add(item.role);
        }
        return roles;
    }

    /** Calculates a one-decimal-place percentage for a role bucket. */
    private static Decimal calculatePercentage(Integer countValue, Integer totalCount) {
        if (totalCount == null || totalCount == 0) {
            return 0;
        }
        return (Decimal.valueOf(countValue) * 100 / totalCount).setScale(1);
    }

    /** Creates a fixed-width text bar for Slack. */
    private static String buildBar(Decimal percentage) {
        Integer filled = Integer.valueOf((percentage / 10).setScale(0, RoundingMode.HALF_UP));
        filled = Math.max(0, Math.min(BAR_WIDTH, filled));
        return repeat('🟩', filled) + repeat('⬜', BAR_WIDTH - filled);
    }

    /** Repeats a text token a fixed number of times. */
    private static String repeat(String token, Integer count) {
        List<String> values = new List<String>();
        for (Integer index = 0; index < count; index++) {
            values.add(token);
        }
        return String.join(values, '');
    }

    /** Formats a decimal without trailing .0 when possible. */
    private static String formatDecimal(Decimal value) {
        return value == value.setScale(0) ? String.valueOf(value.setScale(0)) : String.valueOf(value);
    }

    /** Returns display styling for a role bucket. */
    private static RoleStyle getRoleStyle(String role) {
        return ROLE_STYLES_BY_ROLE.containsKey(role) ? ROLE_STYLES_BY_ROLE.get(role) : ROLE_STYLES_BY_ROLE.get(UNKNOWN_ROLE);
    }

    /** Input options for the summary action. */
    global class Request {
        @InvocableVariable(label='Recent Message Limit' description='返却する最新メッセージ数。未指定時は10件、最大50件です。' required=false)
        global Integer recentMessageLimit;
    }

    /** Output returned to Hosted MCP clients and Agentforce. */
    global class Response {
        @InvocableVariable(label='Success' description='集計が成功したかどうか')
        global Boolean isSuccess;

        @InvocableVariable(label='Total Count' description='集計対象の意気込み投稿数')
        global Integer totalCount;

        @InvocableVariable(label='Role Breakdown JSON' description='参加者種別ごとの件数、割合、絵文字、色、テキストバー')
        global String roleBreakdownJson;

        @InvocableVariable(label='Recent Messages JSON' description='最新の意気込み投稿')
        global String recentMessagesJson;

        @InvocableVariable(label='Slack Text Chart' description='Slack本文にそのまま貼れる絵文字ベースの棒グラフ')
        global String slackTextChart;

        @InvocableVariable(label='QuickChart URL' description='Slack Block Kit imageブロックで表示するグラフ画像URL')
        global String quickChartUrl;

        @InvocableVariable(label='Summary JSON' description='LLMが扱いやすい統合JSONペイロード')
        global String summaryJson;
    }

    /** Raised when the caller lacks access required for the summary. */
    public class EventMessageSummaryException extends Exception {
    }

    private class SummaryData {
        Integer totalCount = 0;
        Map<String, Integer> roleCounts = new Map<String, Integer>();
        List<EventMessage__c> recentMessages = new List<EventMessage__c>();
    }

    private class RoleStyle {
        String emoji;
        String color;

        RoleStyle(String emoji, String color) {
            this.emoji = emoji;
            this.color = color;
        }
    }

    private class RoleBreakdown {
        public String role;
        public Integer count;
        public Decimal percentage;
        public String emoji;
        public String color;
        public String textBar;
    }

    private class RecentMessage {
        public Id id;
        public String role;
        public String enthusiasm;
        public String replyMessage;
        public String status;
        public Datetime createdDate;
    }

    private class RoleSortItem implements Comparable {
        String role;
        Integer countValue;

        RoleSortItem(String role, Integer countValue) {
            this.role = role;
            this.countValue = countValue == null ? 0 : countValue;
        }

        public Integer compareTo(Object other) {
            RoleSortItem otherItem = (RoleSortItem) other;
            if (this.countValue != otherItem.countValue) {
                return this.countValue > otherItem.countValue ? -1 : 1;
            }
            return this.role.compareTo(otherItem.role);
        }
    }
}
