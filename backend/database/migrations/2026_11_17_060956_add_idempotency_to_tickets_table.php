<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Week 15 DEF-02: duplicate-submission protection. The unique index is the
 * final arbiter when two identical requests arrive at the same moment.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tickets', function (Blueprint $table) {
            $table->string('idempotency_key', 64)->nullable()->after('source');
            $table->char('request_hash', 64)->nullable()->after('idempotency_key');
            $table->unique(['requester_id', 'idempotency_key']);
        });
    }

    public function down(): void
    {
        Schema::table('tickets', function (Blueprint $table) {
            $table->dropUnique(['requester_id', 'idempotency_key']);
            $table->dropColumn(['idempotency_key', 'request_hash']);
        });
    }
};
