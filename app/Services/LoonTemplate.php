<?php

namespace App\Services;

class LoonTemplate
{
    private const PROXIES = '{{PROXIES}}';
    private const PROXY_NAMES = '{{PROXY_NAMES}}';

    public static function content(): string
    {
        return subscribe_template('loon') ?: <<<'CONF'
[General]
dns-server = system

[Proxy]
{{PROXIES}}

[Proxy Group]
Proxy = select,{{PROXY_NAMES}}

[Rule]
FINAL,Proxy
CONF;
    }

    public static function isValid(string $template): bool
    {
        $template = self::normalize($template);

        return substr_count($template, self::PROXIES) === 1
            && preg_match('/^\[Proxy\][ \t]*\n(?:(?!\h*\[[^\]\n]+\]\h*$)[^\n]*\n)*?^\h*\{\{PROXIES\}\}\h*$/mi', $template) === 1;
    }

    public static function render(string $template, array $servers, callable $buildProxy): string
    {
        $template = self::normalize($template);
        $lines = [];
        $names = [];
        // Reserve names defined by the template and names of built-in policies.
        preg_match_all('/^\h*([^\[;#=\n][^=\n]*)=/m', $template, $definitions);
        $used = array_fill_keys(array_map(
            static fn (string $name): string => strtolower(trim($name)),
            array_merge($definitions[1], ['DIRECT', 'REJECT'])
        ), true);

        foreach ($servers as $server) {
            $base = trim(preg_replace('/[\x00-\x1f\x7f,=;#{}]+/', ' ', $server['name']));
            $base = $base === '' ? 'Node' : $base;
            $name = $base;
            for ($suffix = 2; isset($used[strtolower($name)]); $suffix++) {
                $name = "{$base} ({$suffix})";
            }

            $server['name'] = $name;
            $line = rtrim((string) $buildProxy($server), "\r\n");
            if ($line === '' || strpbrk($line, "\r\n") !== false) {
                continue;
            }
            $used[strtolower($name)] = true;
            $lines[] = $line;
            $names[] = $name;
        }

        return strtr($template, [
            self::PROXIES => implode("\n", $lines),
            self::PROXY_NAMES => $names ? implode(',', $names) : 'DIRECT',
        ]) . "\n";
    }

    private static function normalize(string $template): string
    {
        return trim(str_replace(["\r\n", "\r"], "\n", $template));
    }
}
