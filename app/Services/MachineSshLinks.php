<?php

namespace App\Services;

class MachineSshLinks
{
    public static function fromConfig(): array
    {
        $gateway = trim((string) config('machine.ssh_gateway_url'));
        if (!filter_var($gateway, FILTER_VALIDATE_URL) || !str_starts_with($gateway, 'https://')) {
            return [];
        }

        $parts = parse_url($gateway);
        if (isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])) {
            return [];
        }

        $connections = json_decode((string) config('machine.ssh_connections'), false, 8);
        if (!$connections instanceof \stdClass) {
            return [];
        }

        $links = [];
        $base = rtrim($gateway, '/') . '/#/client/';
        foreach ($connections as $sid => $clientId) {
            if (preg_match('/\A[1-9][0-9]*\z/', $sid)
                && is_string($clientId)
                && preg_match('/\A[A-Za-z0-9_+\/-]{1,512}={0,2}\z/', $clientId)) {
                $links[$sid] = $base . rtrim(strtr($clientId, '+/', '-_'), '=');
            }
        }

        return $links;
    }
}
