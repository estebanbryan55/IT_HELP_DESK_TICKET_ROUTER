<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class DatabaseSeeder extends Seeder
{
    /** Fictional seed users only. Addresses use reserved .test domains. */
    public function run(): void
    {
        $users = [
            ['req-ana', 'Ana Reyes (Student)', 'requester', 'ana.reyes@students.helpdesk.test', null],
            ['req-ben', 'Ben Santos (Employee)', 'requester', 'ben.santos@staff.helpdesk.test', null],
            // Mailbox decommissioned: every notification to this user is rejected by the gateway (permanent failure).
            ['req-gio', 'Gio Cruz (Alumni account)', 'requester', 'gio.cruz@invalid.test', null],
            ['agent-carla', 'Carla Dizon', 'agent', 'carla@support.helpdesk.test', 'network'],
            ['agent-noel', 'Noel Garcia', 'agent', 'noel@support.helpdesk.test', 'network'],
            ['agent-dan', 'Dan Lim', 'agent', 'dan@support.helpdesk.test', 'software'],
            ['agent-eli', 'Eli Ramos', 'agent', 'eli@support.helpdesk.test', 'hardware'],
            ['agent-faith', 'Faith Torres', 'agent', 'faith@support.helpdesk.test', 'accounts'],
            ['sup-mara', 'Mara Villanueva (Supervisor)', 'supervisor', 'mara@support.helpdesk.test', null],
        ];
        foreach ($users as [$id, $name, $role, $email, $team]) {
            DB::table('users')->updateOrInsert(['id' => $id],
                ['display_name' => $name, 'role' => $role, 'email' => $email, 'team' => $team, 'available' => true]);
        }
    }
}
