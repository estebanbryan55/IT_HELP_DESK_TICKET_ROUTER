<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\LoginRequest;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

class AuthController extends Controller
{
    /** A real hash used to equalise timing when the email does not exist. */
    private const DUMMY_HASH = '$2y$12$1V9MZdrW1WRtc8qRsLR53.friU/B0afwrM2SEmEFcKThl4gZ8Vtjy';

    public function login(LoginRequest $request): JsonResponse
    {
        $user = User::where('email', $request->string('email')->lower())->first();

        // Always run one hash check so a missing account is not faster than a wrong password.
        $valid = Hash::check($request->input('password'), $user?->password ?? self::DUMMY_HASH);

        if (! $user || ! $valid || ! $user->is_active) {
            Log::notice('auth.login_failed', ['user_id' => $user?->id]);

            return response()->json(['message' => 'Invalid credentials.'], 401);
        }

        $ttl = config('security.token_ttl_minutes');
        $token = $user->createToken('flutter-web', $user->role->abilities(), now()->addMinutes($ttl));

        Log::info('auth.login_succeeded', ['user_id' => $user->id]);

        return response()->json([
            'token' => $token->plainTextToken,
            'token_type' => 'Bearer',
            'expires_at' => $token->accessToken->expires_at->toIso8601String(),
            'user' => $this->userPayload($user),
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['user' => $this->userPayload($request->user())]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();
        Log::info('auth.logout', ['user_id' => $request->user()->id]);

        return response()->json(['message' => 'Signed out.']);
    }

    private function userPayload(User $user): array
    {
        return ['id' => $user->id, 'name' => $user->name, 'role' => $user->role->value];
    }
}
