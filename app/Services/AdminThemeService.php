<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class AdminThemeService
{
    private const COLORS = ['background', 'foreground', 'card', 'card-foreground', 'popover',
        'popover-foreground', 'primary', 'primary-foreground', 'secondary', 'secondary-foreground',
        'muted', 'muted-foreground', 'accent', 'accent-foreground', 'destructive',
        'destructive-foreground', 'border', 'input', 'ring'];
    private const COLOR_PATTERN = '/\A(?:[0-9]{1,2}|[12][0-9]{2}|3[0-5][0-9]|360) (?:[0-9]{1,2}|100)% (?:[0-9]{1,2}|100)%\z/';

    public function builtin(): array
    {
        $themes = [];
        if (!is_file(public_path('assets/admin/themes/base.css'))) {
            return $themes;
        }
        foreach (glob(public_path('assets/admin/themes/*/theme.css')) ?: [] as $file) {
            $id = basename(dirname($file));
            if ($id !== 'default' && preg_match('/\A[a-z][a-z0-9-]*\z/', $id) && is_readable($file)) {
                $themes[$id] = "assets/admin/themes/{$id}/theme.css";
            }
        }
        ksort($themes);

        return $themes;
    }

    public function uploaded(): array
    {
        $themes = admin_setting('admin_theme_uploads', []);
        return is_array($themes) ? $themes : [];
    }

    public function selected(): string
    {
        $selected = admin_setting('admin_theme_selected', config('app.admin_theme', 'minimal'));
        return is_string($selected) && in_array($selected, $this->ids(), true) ? $selected : 'default';
    }

    public function ids(): array
    {
        return array_merge(['default'], array_keys($this->builtin()), array_keys($this->uploaded()));
    }

    public function upload(string $json): string
    {
        try {
            $data = json_decode($json, true, 8, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw ValidationException::withMessages(['theme' => '主题文件必须是有效的 JSON。']);
        }
        if (!is_array($data) || array_diff(array_keys($data), ['id', 'light', 'dark'])) {
            throw ValidationException::withMessages(['theme' => '只允许 id、light 和 dark 字段。']);
        }

        $rules = [
            'id' => ['required', 'string', 'regex:/\A[a-z][a-z0-9-]{0,39}\z/'],
            'light' => ['required', 'array:' . implode(',', self::COLORS)],
            'dark' => ['required', 'array:' . implode(',', self::COLORS)],
            'light.*' => ['required', 'string', 'regex:' . self::COLOR_PATTERN],
            'dark.*' => ['required', 'string', 'regex:' . self::COLOR_PATTERN],
        ];
        $theme = Validator::make($data, $rules)->validate();
        $id = $theme['id'];

        Cache::store('redis')->lock('admin-theme-upload', 10)->block(3, function () use ($id, $theme) {
            $saved = $this->uploaded();
            if (in_array($id, $this->ids(), true)) {
                throw ValidationException::withMessages(['theme' => '该主题 ID 已存在，请换一个名称。']);
            }
            if (count($saved) >= 20) {
                throw ValidationException::withMessages(['theme' => '最多可上传 20 套主题。']);
            }
            $saved[$id] = ['light' => $theme['light'], 'dark' => $theme['dark']];
            admin_setting(['admin_theme_uploads' => $saved]);
        });

        return $id;
    }

    public function css(string $id): string
    {
        $theme = $this->uploaded()[$id] ?? [];
        $css = '';
        foreach (['light' => '', 'dark' => '.dark'] as $mode => $suffix) {
            $declarations = '';
            foreach (self::COLORS as $color) {
                $value = $theme[$mode][$color] ?? null;
                if (is_string($value) && preg_match(self::COLOR_PATTERN, $value)) {
                    $declarations .= "--{$color}:{$value};";
                }
            }
            $css .= ":root[data-admin-theme=\"minimal\"]{$suffix}{{$declarations}}";
        }
        return $css;
    }
}
