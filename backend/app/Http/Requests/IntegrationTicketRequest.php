<?php

namespace App\Http\Requests;

use App\Enums\TicketCategory;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class IntegrationTicketRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'requester_email' => ['required', 'email:rfc', 'max:120'],
            'category' => ['required', Rule::enum(TicketCategory::class)],
            'subject' => ['required', 'string', 'min:5', 'max:120'],
            'description' => ['required', 'string', 'min:10', 'max:2000'],
        ];
    }
}
