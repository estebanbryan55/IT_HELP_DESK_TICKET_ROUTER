<?php

namespace App\Services;

use App\Models\Ticket;

/**
 * Rule-based categorisation. Rules live in config/routing_rules.json so support staff
 * can tune keywords without a code change.
 */
class RoutingRules
{
    /**
     * @param array<string, array{team: string, keywords: list<string>}> $categories
     * @param array<string, list<string>> $priorityRaise
     */
    public function __construct(public readonly array $categories, public readonly array $priorityRaise) {}

    public static function load(string $path): self
    {
        $j = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);
        $lower = fn (array $words) => array_map(fn ($w) => mb_strtolower($w), $words);
        $categories = [];
        foreach ($j['categories'] as $name => $c) {
            $categories[$name] = ['team' => $c['team'], 'keywords' => $lower($c['keywords'])];
        }
        $raise = [];
        foreach ($j['priorityRaise'] ?? [] as $level => $words) {
            $raise[$level] = $lower($words);
        }

        return new self($categories, $raise);
    }

    public function teamFor(string $category): ?string
    {
        return $this->categories[$category]['team'] ?? null;
    }

    /** @return array{category: string, priority: string, team: ?string, reason: string} A null team means a supervisor must triage. */
    public function decide(string $title, string $description, string $requestedCategory, string $requestedPriority): array
    {
        $text = mb_strtolower("$title $description");
        $reasons = [];

        // 1. Category: requester's explicit choice wins; otherwise keyword scoring.
        if ($requestedCategory !== 'auto' && $requestedCategory !== 'other') {
            $category = $requestedCategory;
            $reasons[] = 'category chosen by requester';
        } else {
            $scores = [];
            foreach ($this->categories as $name => $c) {
                $scores[$name] = count(array_filter($c['keywords'], fn ($k) => str_contains($text, $k)));
            }
            $best = max([0, ...array_values($scores)]);
            $leaders = $best > 0 ? array_keys(array_filter($scores, fn ($s) => $s === $best)) : [];
            if (count($leaders) === 1) {
                $category = $leaders[0];
                $reasons[] = "keyword match: $category ($best hit".($best === 1 ? '' : 's').')';
            } elseif ($leaders === []) {
                $category = 'other';
                $reasons[] = 'no keyword matched';
            } else {
                $category = 'other';
                $reasons[] = 'ambiguous keywords: '.implode(', ', $leaders);
            }
        }

        // 2. Priority: rules may raise, never lower, the requester's priority.
        $priority = $requestedPriority;
        foreach (['critical', 'high'] as $level) {
            $hit = null;
            foreach ($this->priorityRaise[$level] ?? [] as $w) {
                if (str_contains($text, $w)) {
                    $hit = $w;
                    break;
                }
            }
            if ($hit !== null && Ticket::priorityRank($level) > Ticket::priorityRank($priority)) {
                $reasons[] = "priority raised $priority -> $level by keyword \"$hit\"";
                $priority = $level;
                break;
            }
        }

        return ['category' => $category, 'priority' => $priority, 'team' => $this->teamFor($category), 'reason' => implode('; ', $reasons)];
    }
}
