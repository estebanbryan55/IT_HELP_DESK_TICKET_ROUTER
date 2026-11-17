<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // requester (student/employee), agent, supervisor
            $table->string('role', 20)->default('requester')->after('password');
            // Category an agent is routed by the rule-based assignment (null for non-agents).
            $table->string('specialization', 20)->nullable()->after('role');
            $table->boolean('is_active')->default(true)->after('specialization');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['role', 'specialization', 'is_active']);
        });
    }
};
