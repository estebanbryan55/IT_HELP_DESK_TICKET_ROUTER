<?php

namespace App\Models;

use App\Services\Clock;
use Illuminate\Database\Eloquent\Model;

/** A notification waiting in the transactional outbox. */
class OutboxMessage extends Model
{
    public const PENDING = 'pending';
    public const SENDING = 'sending';
    public const RETRYING = 'retrying';
    public const SENT = 'sent';
    public const DEAD_LETTER = 'dead_letter';
    public const DISMISSED = 'dismissed';

    public const DUE = [self::PENDING, self::RETRYING];

    public $incrementing = false;
    public $timestamps = false;
    protected $keyType = 'string';
    protected $dateFormat = 'Y-m-d H:i:s.v';
    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'created_at' => 'immutable_datetime',
            'next_attempt_at' => 'immutable_datetime',
            'sent_at' => 'immutable_datetime',
            'attempts' => 'integer',
            'attempt_log' => 'array',
        ];
    }

    public static function maskAddress(string $a): string
    {
        $at = strpos($a, '@');
        if ($at === false || $at <= 1) {
            return '***';
        }

        return $a[0].'***'.substr($a, $at);
    }

    /** Client view: the recipient address is masked and the body is left out. */
    public function toPublic(): array
    {
        return [
            'id' => $this->id,
            'idempotencyKey' => $this->idempotency_key,
            'ticketId' => $this->ticket_id,
            'event' => $this->event,
            'recipientId' => $this->recipient_id,
            'recipientAddress' => self::maskAddress($this->recipient_address),
            'subject' => $this->subject,
            'correlationId' => $this->correlation_id,
            'createdAt' => Clock::iso($this->created_at),
            'status' => $this->status,
            'attempts' => $this->attempts,
            'nextAttemptAt' => Clock::iso($this->next_attempt_at),
            'sentAt' => Clock::iso($this->sent_at),
            'lastErrorCode' => $this->last_error_code,
            'deadLetterReason' => $this->dead_letter_reason,
            'resolutionNote' => $this->resolution_note,
            'attemptLog' => array_values($this->attempt_log ?? []),
        ];
    }
}
