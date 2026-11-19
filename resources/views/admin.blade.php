<!DOCTYPE html>
@php
    $adminThemes = app(\App\Services\AdminThemeService::class);
    $selectedAdminTheme = $adminThemes->selected();
    $builtinAdminThemes = $adminThemes->builtin();
    $uploadedAdminTheme = isset($adminThemes->uploaded()[$selectedAdminTheme]);
    $adminTheme = $uploadedAdminTheme ? 'minimal' : $selectedAdminTheme;
    $adminThemeFile = $builtinAdminThemes[$adminTheme] ?? null;
@endphp
<html lang="en" @if($adminThemeFile) data-admin-theme="{{ $adminTheme }}" @endif>

<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{{ $title }}</title>
  <script>
    window.settings = {
      base_url: "/",
      title: "{{ $title }}",
      version: "{{ $version }}",
      logo: "{{ $logo }}",
      secure_path: "{{ $secure_path }}",
    };
  </script>
  @php
    $manifestPath = public_path('assets/admin/manifest.json');
    $manifest = file_exists($manifestPath) ? json_decode(file_get_contents($manifestPath), true) : null;
    $entry = is_array($manifest) ? ($manifest['index.html'] ?? null) : null;
    $scripts = [];
    $styles = [];
    $locales = [];

    if (is_array($entry)) {
      $visited = [];
      $collectAssets = function ($chunkName) use (&$collectAssets, &$manifest, &$visited, &$scripts, &$styles) {
        if (isset($visited[$chunkName]) || !isset($manifest[$chunkName]) || !is_array($manifest[$chunkName])) {
          return;
        }

        $visited[$chunkName] = true;
        $chunk = $manifest[$chunkName];

        if (!empty($chunk['css']) && is_array($chunk['css'])) {
          foreach ($chunk['css'] as $cssFile) {
            $styles[$cssFile] = $cssFile;
          }
        }

        if (!empty($chunk['imports']) && is_array($chunk['imports'])) {
          foreach ($chunk['imports'] as $import) {
            $collectAssets($import);
          }
        }

        if (!empty($chunk['isEntry']) && !empty($chunk['file'])) {
          $scripts[$chunk['file']] = $chunk['file'];
        }
      };

      $collectAssets('index.html');
    }

    foreach (glob(public_path('assets/admin/locales/*.js')) ?: [] as $localeFile) {
      $locales['locales/' . basename($localeFile)] = hash_file('sha256', $localeFile);
    }
    ksort($locales);
  @endphp

  @if($entry && count($scripts) > 0)
    @foreach($styles as $css)
      <link rel="stylesheet" crossorigin href="/assets/admin/{{ $css }}" />
    @endforeach
    @foreach($locales as $locale => $localeHash)
      <script src="/assets/admin/{{ $locale }}?v={{ $localeHash }}"></script>
    @endforeach
    <script src="{{ asset('js/admin-loon-translations.js') }}?v={{ $version }}"></script>
    @foreach($scripts as $js)
      <script type="module" crossorigin src="/assets/admin/{{ $js }}"></script>
    @endforeach
  @else
    {{-- Fallback: hardcoded paths for backward compatibility --}}
    <script type="module" crossorigin src="/assets/admin/assets/index.js"></script>
    <link rel="stylesheet" crossorigin href="/assets/admin/assets/index.css" />
    <link rel="stylesheet" crossorigin href="/assets/admin/assets/vendor.css">
    <script src="/assets/admin/locales/en-US.js"></script>
    <script src="/assets/admin/locales/zh-CN.js"></script>
    <script src="/assets/admin/locales/ru-RU.js"></script>
    <script src="{{ asset('js/admin-loon-translations.js') }}?v={{ $version }}"></script>
  @endif
  @if($adminThemeFile)
    <link rel="stylesheet" href="{{ asset('assets/admin/themes/base.css') }}" />
    <link rel="stylesheet" href="{{ asset($adminThemeFile) }}" />
    @if($uploadedAdminTheme)
      <style>{!! $adminThemes->css($selectedAdminTheme) !!}</style>
    @endif
  @endif
  <link rel="stylesheet" href="{{ asset('css/admin-theme-picker.css') }}?v={{ $version }}" />
  <script src="{{ asset('js/admin-theme-picker.js') }}?v={{ $version }}" defer></script>
  <link rel="stylesheet" href="{{ asset('css/admin-node-installer.css') }}?v={{ $version }}" />
</head>

<body>
  <div id="root"></div>
  <template id="xboard-admin-theme-template" data-endpoint="{{ route('admin-theme.index', [], false) }}">
    <input type="file" name="theme" accept=".json,application/json" hidden aria-label="上传 JSON 色板">
    <p class="xboard-admin-theme-status text-muted-foreground" role="status"></p>
    <section class="xboard-admin-theme-grid" aria-label="可用的后台主题"></section>
  </template>
</body>

</html>
