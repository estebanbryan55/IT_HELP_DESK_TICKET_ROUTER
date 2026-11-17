<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Nonces of accepted signed integration messages, kept for replay detection.
        Schema::create('integration_nonces', function (Blueprint $table) {
            $table->id();
            $table->string('key_id', 40);
            $table->string('nonce', 64);
            $table->timestamp('received_at');

            $table->unique(['key_id', 'nonce']);
            $table->index('received_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('integration_nonces');
    }
};
