<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Replay protection only needs nonces younger than the signature tolerance window;
// older rows are rejected by the timestamp check anyway, so prune them hourly.
Schedule::call(fn () => \App\Models\IntegrationNonce::where(
    'received_at', '<', now()->subSeconds(2 * config('security.integration.tolerance_seconds'))
)->delete())->hourly()->name('prune-integration-nonces');
