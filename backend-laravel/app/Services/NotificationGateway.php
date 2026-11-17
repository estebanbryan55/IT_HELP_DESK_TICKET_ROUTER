<?php

namespace App\Services;

use App\Models\OutboxMessage;

interface NotificationGateway
{
    public function send(OutboxMessage $message): SendResult;

    public function ping(): bool;
}
