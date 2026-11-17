<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// All timestamps are stored in UTC with millisecond precision.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $t) {
            $t->string('id', 64)->primary();
            $t->string('display_name');
            $t->string('role', 20);
            $t->string('email');
            $t->string('team', 40)->nullable();
            $t->boolean('available')->default(true);
        });

        Schema::create('tickets', function (Blueprint $t) {
            $t->string('id', 20)->primary();
            $t->string('title', 120);
            $t->text('description');
            $t->string('requested_category', 20);
            $t->string('requested_priority', 20);
            $t->string('category', 20);
            $t->string('priority', 20);
            $t->string('status', 20)->index();
            $t->string('requester_id', 64)->index();
            $t->string('assignee_id', 64)->nullable()->index();
            $t->string('team', 40)->nullable();
            $t->dateTime('created_at', 3);
            $t->dateTime('updated_at', 3);
            $t->dateTime('sla_due_at', 3);
            $t->dateTime('resolved_at', 3)->nullable();
            $t->dateTime('closed_at', 3)->nullable();
            $t->text('routing_reason');
            $t->boolean('escalated')->default(false);
            $t->json('alerts');
            $t->foreign('requester_id')->references('id')->on('users');
            $t->foreign('assignee_id')->references('id')->on('users');
        });

        Schema::create('ticket_events', function (Blueprint $t) {
            $t->id();
            $t->string('ticket_id', 20);
            $t->dateTime('at', 3);
            $t->string('actor', 64);
            $t->string('action', 40);
            $t->string('from', 64)->nullable();
            $t->string('to', 64)->nullable();
            $t->text('note')->nullable();
            $t->string('correlation_id', 64)->nullable();
            $t->foreign('ticket_id')->references('id')->on('tickets')->cascadeOnDelete();
        });

        Schema::create('ticket_responses', function (Blueprint $t) {
            $t->id();
            $t->string('ticket_id', 20);
            $t->dateTime('at', 3);
            $t->string('author_id', 64);
            $t->text('message');
            $t->foreign('ticket_id')->references('id')->on('tickets')->cascadeOnDelete();
        });

        // userId:Idempotency-Key -> ticket, so a resubmitted form does not create a duplicate.
        Schema::create('ticket_idempotency_keys', function (Blueprint $t) {
            $t->string('key', 140)->primary();
            $t->string('ticket_id', 20);
        });

        Schema::create('outbox_messages', function (Blueprint $t) {
            $t->string('id', 20)->primary();
            $t->string('idempotency_key', 191)->unique();
            $t->string('ticket_id', 20)->nullable()->index();
            $t->string('event', 40);
            $t->string('recipient_id', 64);
            $t->string('recipient_address');
            $t->string('subject');
            $t->text('body');
            $t->string('correlation_id', 64);
            $t->dateTime('created_at', 3);
            $t->string('status', 20);
            $t->unsignedInteger('attempts')->default(0);
            $t->dateTime('next_attempt_at', 3);
            $t->dateTime('sent_at', 3)->nullable();
            $t->string('last_error_code', 64)->nullable();
            $t->string('dead_letter_reason', 40)->nullable();
            $t->text('resolution_note')->nullable();
            $t->json('attempt_log');
            $t->index(['status', 'next_attempt_at']);
        });

        Schema::create('job_runs', function (Blueprint $t) {
            $t->id('seq'); // insertion order
            $t->string('id', 64)->unique();
            $t->string('job', 40)->index();
            $t->string('trigger', 20);
            $t->dateTime('started_at', 3);
            $t->dateTime('finished_at', 3)->nullable();
            $t->string('status', 20);
            $t->json('stats');
            $t->string('correlation_id', 64);
        });

        Schema::create('support_summaries', function (Blueprint $t) {
            $t->string('id', 20)->primary();
            $t->unsignedInteger('seq')->unique();
            $t->string('date', 10);
            $t->dateTime('generated_at', 3);
            $t->string('trigger', 20);
            $t->json('data');
        });

        // Sequence counters (ticket, message, summary) and small runtime state (dev clock offset).
        Schema::create('app_state', function (Blueprint $t) {
            $t->string('key', 40)->primary();
            $t->bigInteger('value')->default(0);
        });
        DB::table('app_state')->insert([['key' => 'lock', 'value' => 0], ['key' => 'clock_offset_seconds', 'value' => 0]]);
    }

    public function down(): void
    {
        foreach (['app_state', 'support_summaries', 'job_runs', 'outbox_messages', 'ticket_idempotency_keys',
            'ticket_responses', 'ticket_events', 'tickets', 'users'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
