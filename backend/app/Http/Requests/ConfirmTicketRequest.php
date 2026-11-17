<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class ConfirmTicketRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'accepted' => ['required', 'boolean'],
            'note' => ['required_if:accepted,false', 'nullable', 'string', 'max:500'],
        ];
    }
}
