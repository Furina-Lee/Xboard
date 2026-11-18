<!DOCTYPE html>
@php
    $adminThemeUrls = [];
    if (is_file(public_path('assets/admin/themes/base.css'))) {
        foreach (glob(public_path('assets/admin/themes/*/theme.css')) ?: [] as $themeFile) {
            $id = basename(dirname($themeFile));
            if ($id !== 'default' && preg_match('/\A[a-z][a-z0-9-]*\z/', $id) && is_readable($themeFile)) {
                $adminThemeUrls[$id] = asset("assets/admin/themes/{$id}/theme.css");
            }
        }
    }
    ksort($adminThemeUrls);
    $configuredTheme = config('app.admin_theme', 'minimal');
    $adminTheme = is_string($configuredTheme) && isset($adminThemeUrls[$configuredTheme])
        ? $configuredTheme : 'default';
@endphp
<html lang="en" @if($adminTheme !== 'default') data-admin-theme="{{ $adminTheme }}" @endif>

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
      <script src="/assets/admin/{{ $locale }}"></script>
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
  @if($adminThemeUrls)
    <link rel="stylesheet" href="{{ asset('assets/admin/themes/base.css') }}" />
    <link id="xboard-admin-theme-css" rel="stylesheet" @if($adminTheme !== 'default') href="{{ $adminThemeUrls[$adminTheme] }}" @endif />
    <script src="{{ asset('js/admin-theme-picker.js') }}" data-themes="{{ json_encode($adminThemeUrls, JSON_THROW_ON_ERROR) }}" data-site-theme="{{ $adminTheme }}"></script>
    <link rel="stylesheet" href="{{ asset('css/admin-theme-picker.css') }}" />
  @endif
</head>

<body>
  <div id="root"></div>
  @if($adminThemeUrls)
    <details class="xboard-admin-theme-picker" id="xboard-admin-theme-picker" hidden>
      <summary>后台主题</summary>
      <label for="xboard-admin-theme-choice">当前浏览器的主题</label>
      <select id="xboard-admin-theme-choice">
        <option value="">跟随站点设置</option>
        <option value="default">原始主题</option>
        @foreach($adminThemeUrls as $id => $url)
          <option value="{{ $id }}">{{ $id === 'minimal' ? '简约主题' : $id }}</option>
        @endforeach
      </select>
    </details>
  @endif
</body>

</html>
