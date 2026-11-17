<?php

namespace App\Http\Requests;

use App\Enums\TicketStatus;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class TransitionTicketRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'status' => ['required', Rule::enum(TicketStatus::class)->only([
                TicketStatus::InProgress, TicketStatus::Resolved,
            ])],
            'note' => ['required_if:status,resolved', 'nullable', 'string', 'max:500'],
        ];
    }
}
