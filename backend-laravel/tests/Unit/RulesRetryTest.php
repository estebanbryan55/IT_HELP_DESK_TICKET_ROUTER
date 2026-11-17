<?php

namespace Tests\Unit;

use App\Services\RetryPolicy;
use App\Services\RoutingRules;
use PHPUnit\Framework\TestCase;

class RulesRetryTest extends TestCase
{
    private function decide(string $title, string $desc, string $category = 'auto', string $priority = 'medium'): array
    {
        return RoutingRules::load(__DIR__.'/../../config/routing_rules.json')->decide($title, $desc, $category, $priority);
    }

    public function test_routes_by_keyword_to_the_matching_team(): void
    {
        $d = $this->decide('VPN will not connect', 'The vpn says no connection from home.');
        $this->assertSame('network', $d['category']);
        $this->assertSame('network', $d['team']);
    }

    public function test_explicit_category_from_requester_wins_over_keywords(): void
    {
        $d = $this->decide('Printer and wifi', 'printer is jammed', 'hardware');
        $this->assertSame('hardware', $d['category']);
        $this->assertStringContainsString('requester', $d['reason']);
    }

    public function test_no_keyword_match_goes_to_triage(): void
    {
        $d = $this->decide('Question about something', 'I have a general question for the office.');
        $this->assertSame('other', $d['category']);
        $this->assertNull($d['team']);
    }

    public function test_equal_keyword_scores_are_ambiguous_and_go_to_triage(): void
    {
        $d = $this->decide('Printer on the network', 'printer cannot reach the network');
        $this->assertNull($d['team']);
        $this->assertStringContainsString('ambiguous', $d['reason']);
    }

    public function test_priority_keywords_raise_but_never_lower_priority(): void
    {
        $this->assertSame('critical', $this->decide('Internet outage', 'whole building has no internet')['priority']);
        $this->assertSame('high', $this->decide('Monitor flicker', 'urgent for my exam', priority: 'low')['priority']);
        $this->assertSame('critical', $this->decide('Monitor flicker', 'urgent for my exam', priority: 'critical')['priority']);
    }

    public function test_delay_grows_exponentially_and_stays_within_jitter_bounds_and_the_cap(): void
    {
        mt_srand(1);
        $policy = new RetryPolicy(4, 2000, 30000, mt_rand(...));
        for ($attempt = 1; $attempt <= 8; $attempt++) {
            $exp = min(30000, 2000 * 2 ** ($attempt - 1));
            $d = $policy->delayAfter($attempt);
            $this->assertGreaterThanOrEqual(intdiv($exp, 2), $d, "attempt $attempt");
            $this->assertLessThanOrEqual($exp, $d, "attempt $attempt");
        }
    }

    public function test_attempt_budget_is_bounded(): void
    {
        $policy = new RetryPolicy(4, 2000, 30000);
        $this->assertTrue($policy->canRetry(3));
        $this->assertFalse($policy->canRetry(4));
    }

    public function test_http_status_classification(): void
    {
        $this->assertSame('none', RetryPolicy::classifyHttpStatus(202));
        foreach ([408, 429, 500, 502, 503] as $s) {
            $this->assertSame('transient', RetryPolicy::classifyHttpStatus($s), "$s");
        }
        foreach ([400, 401, 403, 404, 422] as $s) {
            $this->assertSame('permanent', RetryPolicy::classifyHttpStatus($s), "$s");
        }
    }
}
