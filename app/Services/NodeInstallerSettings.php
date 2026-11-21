<?php

namespace App\Services;

class NodeInstallerSettings
{
    public static function url(): string
    {
        return self::value('node_installer_url', 'machine.installer_url');
    }

    public static function version(): string
    {
        return self::value('node_installer_version', 'machine.installer_version');
    }

    public static function instance(): string
    {
        return self::value('node_installer_instance', 'machine.installer_instance');
    }

    private static function value(string $key, string $configKey): string
    {
        $saved = admin_setting($key);
        $value = is_array($saved) ? ($saved['value'] ?? null) : $saved;

        return is_string($value) && $value !== '' ? $value : (string) config($configKey);
    }
}
