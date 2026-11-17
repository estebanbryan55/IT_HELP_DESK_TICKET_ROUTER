<?php

namespace App\Http\Requests;

use App\Enums\TicketCategory;
use App\Enums\TicketPriority;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Server-side validation is authoritative; the Flutter form mirrors these rules
 * only for faster feedback. Only fields needed to route and resolve a ticket
 * are accepted (data minimisation); unknown fields are ignored.
 */
class StoreTicketRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'category' => ['required', Rule::enum(TicketCategory::class)],
            'priority' => ['sometimes', Rule::enum(TicketPriority::class)],
            'subject' => ['required', 'string', 'min:5', 'max:120'],
            'description' => ['required', 'string', 'min:10', 'max:2000'],
            'asset_tag' => ['nullable', 'string', 'regex:/^[A-Z0-9\-]{3,30}$/'],
            'contact_number' => ['nullable', 'string', 'regex:/^\+?[0-9 \-]{7,20}$/'],
            'access_note' => ['nullable', 'string', 'max:300'],
        ];
    }

    public function messages(): array
    {
        return [
            'asset_tag.regex' => 'Asset tag may contain only uppercase letters, digits, and hyphens.',
            'contact_number.regex' => 'Contact number must contain 7-20 digits, spaces, or hyphens.',
        ];
    }
}
