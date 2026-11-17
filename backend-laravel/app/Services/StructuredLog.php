<?php

namespace App\Services;

/** Structured JSON-lines logger. Sensitive field names are redacted before writing. */
class StructuredLog
{
    private const SENSITIVE = [
        'password', 'token', 'authorization', 'apikey', 'api_key', 'secret',
        'email', 'address', 'to', 'title', 'description', 'message', 'body',
    ];

    /** Last records kept in memory so tests can assert on log output. @var list<array<string, mixed>> */
    public array $recent = [];

    public function __construct(private readonly Clock $clock, private readonly ?string $path) {}

    public function info(string $event, array $fields = []): void
    {
        $this->write('INFO', $event, $fields);
    }

    public function warn(string $event, array $fields = []): void
    {
        $this->write('WARN', $event, $fields);
    }

    public function error(string $event, array $fields = []): void
    {
        $this->write('ERROR', $event, $fields);
    }

    private function write(string $level, string $event, array $fields): void
    {
        $record = ['ts' => Clock::iso($this->clock->now()), 'level' => $level, 'event' => $event];
        foreach ($fields as $k => $v) {
            $record[$k] = in_array(strtolower($k), self::SENSITIVE, true) ? '[REDACTED]' : $v;
        }
        $this->recent[] = $record;
        if (count($this->recent) > 500) {
            array_shift($this->recent);
        }
        if ($this->path !== null) {
            if (! is_dir(dirname($this->path))) {
                mkdir(dirname($this->path), 0775, true);
            }
            file_put_contents($this->path, json_encode($record, JSON_UNESCAPED_SLASHES)."\n", FILE_APPEND | LOCK_EX);
        }
    }
}
