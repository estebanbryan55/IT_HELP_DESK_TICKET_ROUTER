<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Enums\TicketCategory;
use App\Models\User;
use App\Services\TicketRouter;
use Illuminate\Database\Seeder;

/**
 * Controlled demo data only: fictional people on the reserved example.test
 * domain. The shared demo password is for local/lab use and must never be
 * used on a deployed environment.
 */
class DatabaseSeeder extends Seeder
{
    public const DEMO_PASSWORD = 'Demo-Pass-2026!';

    public function run(TicketRouter $router): void
    {
        $make = fn (string $name, string $email, Role $role, ?TicketCategory $spec = null) => User::create([
            'name' => $name,
            'email' => $email,
            'password' => self::DEMO_PASSWORD,
            'role' => $role,
            'specialization' => $spec,
            'email_verified_at' => now(),
        ]);

        $student = $make('Sam Student', 'student@example.test', Role::Requester);
        $employee = $make('Erin Employee', 'employee@example.test', Role::Requester);
        $make('Hana Hardware', 'agent.hardware@example.test', Role::Agent, TicketCategory::Hardware);
        $make('Nico Network', 'agent.network@example.test', Role::Agent, TicketCategory::Network);
        $make('Ari Accounts', 'agent.accounts@example.test', Role::Agent, TicketCategory::Account);
        $make('Sol Supervisor', 'supervisor@example.test', Role::Supervisor);

        $router->open($student, [
            'category' => 'network',
            'priority' => 'high',
            'subject' => 'Wi-Fi drops in Library 2F',
            'description' => 'Connection to the campus Wi-Fi drops every few minutes on the second floor of the library.',
            'contact_number' => '0917 555 0101',
        ]);

        $router->open($employee, [
            'category' => 'hardware',
            'subject' => 'Projector not detected in Room 305',
            'description' => 'The ceiling projector does not detect the HDMI input from the teacher laptop.',
            'asset_tag' => 'PRJ-305-01',
            'access_note' => 'Room key is with the department secretary.',
        ]);
    }
}
