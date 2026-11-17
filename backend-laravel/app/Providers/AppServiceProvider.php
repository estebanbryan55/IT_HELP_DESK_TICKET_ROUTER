<?php

namespace App\Providers;

use App\Services\Clock;
use App\Services\HttpNotificationGateway;
use App\Services\JobRunner;
use App\Services\NotificationGateway;
use App\Services\Outbox;
use App\Services\RetryPolicy;
use App\Services\RoutingRules;
use App\Services\Store;
use App\Services\StructuredLog;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /** Wires every component together. Tests swap the gateway, retry policy or log. */
    public function register(): void
    {
        $this->app->singleton(Clock::class);
        $this->app->singleton(Store::class);
        $this->app->singleton(StructuredLog::class, fn ($app) => new StructuredLog(
            $app->make(Clock::class),
            ($path = config('helpdesk.log_file')) === 'none' ? null : base_path($path),
        ));
        $this->app->singleton(RoutingRules::class, fn () => RoutingRules::load(base_path(config('helpdesk.rules_file'))));
        $this->app->singleton(RetryPolicy::class, fn () => new RetryPolicy(
            config('helpdesk.retry.max_attempts'),
            config('helpdesk.retry.base_delay_ms'),
            config('helpdesk.retry.max_delay_ms'),
        ));
        $this->app->singleton(NotificationGateway::class, function () {
            $key = config('helpdesk.gateway.api_key');
            if ($key === null || $key === '') {
                throw new \RuntimeException('GATEWAY_API_KEY is not set. Copy .env.example to .env and set a local value.');
            }

            return new HttpNotificationGateway(config('helpdesk.gateway.url'), $key, config('helpdesk.gateway.timeout_ms'));
        });
        $this->app->singleton(Outbox::class, function ($app) {
            $outbox = new Outbox(
                $app->make(Store::class),
                $app->make(NotificationGateway::class),
                $app->make(RetryPolicy::class),
                $app->make(Clock::class),
                $app->make(StructuredLog::class),
                config('helpdesk.outbox_batch_size'),
                (int) ceil(config('helpdesk.gateway.timeout_ms') / 1000) + 30,
            );
            // Event-driven delivery: start a dispatch in a background process instead of waiting for the next poll.
            // Its claim step waits on the store lock, so it only sees the messages once this transaction commits.
            if (config('helpdesk.event_dispatch')) {
                $spawned = false;
                $outbox->onEnqueued = function () use (&$spawned) {
                    if (! $spawned) {
                        $spawned = true;
                        self::spawnArtisan('helpdesk:job outbox-dispatch --trigger=event');
                    }
                };
            }

            return $outbox;
        });
    }

    public function boot(): void {}

    /** Starts "php artisan <command>" detached, without waiting for it. */
    private static function spawnArtisan(string $command): void
    {
        $php = escapeshellarg(PHP_BINARY);
        $artisan = escapeshellarg(base_path('artisan'));
        if (PHP_OS_FAMILY === 'Windows') {
            pclose(popen("start \"\" /B $php $artisan $command > NUL 2>&1", 'r'));
        } else {
            exec("$php $artisan $command > /dev/null 2>&1 &");
        }
    }
}
