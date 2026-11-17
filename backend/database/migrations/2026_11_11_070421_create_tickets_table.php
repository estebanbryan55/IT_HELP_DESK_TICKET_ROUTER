<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tickets', function (Blueprint $table) {
            $table->id();
            $table->string('reference', 20)->unique();
            $table->foreignId('requester_id')->constrained('users');
            $table->foreignId('assigned_agent_id')->nullable()->constrained('users');
            $table->string('category', 20);
            $table->string('priority', 10)->default('normal');
            $table->string('status', 20)->default('open');
            $table->string('source', 20)->default('web');
            $table->string('subject', 120);
            $table->text('description');
            $table->string('asset_tag', 30)->nullable();
            // Confidential fields: stored with authenticated encryption (see App\Casts\ProtectedString).
            $table->text('contact_number')->nullable();
            $table->text('access_note')->nullable();
            $table->text('resolution_note')->nullable();
            $table->timestamp('sla_due_at')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->index(['status', 'sla_due_at']);
            $table->index('assigned_agent_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tickets');
    }
};
