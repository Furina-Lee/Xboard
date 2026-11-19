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
      $locales[] = 'locales/' . basename($localeFile);
    }
    sort($locales);
  @endphp

  @if($entry && count($scripts) > 0)
    @foreach($styles as $css)
      <link rel="stylesheet" crossorigin href="/assets/admin/{{ $css }}" />
    @endforeach
    @foreach($locales as $locale)
      <script src="/assets/admin/{{ $locale }}?v={{ $version }}"></script>
    @endforeach
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
    <script src="/assets/admin/locales/ko-KR.js"></script>
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
</head>

<body>
  <div id="root"></div>
  <template id="xboard-admin-theme-template" data-endpoint="{{ route('admin-theme.index', [], false) }}">
    <header class="xboard-admin-theme-heading">
      <div>
        <h1 class="text-2xl font-bold tracking-tight">后台主题</h1>
        <p class="text-muted-foreground">所有管理员共用同一套后台主题，其他管理员刷新后即可看到变更。</p>
      </div>
      <form class="xboard-admin-theme-upload">
        <label for="xboard-admin-theme-file">上传主题（JSON，最多 4 KB）</label>
        <input id="xboard-admin-theme-file" name="theme" type="file" accept=".json,application/json" required>
        <button class="xboard-admin-theme-button" type="submit" disabled>校验并保存</button>
      </form>
    </header>
    <p class="xboard-admin-theme-status text-muted-foreground" role="status"></p>
    <section class="xboard-admin-theme-grid" aria-label="可用的后台主题"></section>
  </template>
</body>

</html>
