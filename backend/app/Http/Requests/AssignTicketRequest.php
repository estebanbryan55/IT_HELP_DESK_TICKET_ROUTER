<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class AssignTicketRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'agent_id' => ['required', 'integer'],
            'note' => ['nullable', 'string', 'max:500'],
        ];
    }
}
