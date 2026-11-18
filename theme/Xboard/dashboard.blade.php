@php($assetPath = asset('assets/user/xboard/achen-1.4.4'))
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
  <meta name="theme-color" content="#f5f5f7" />
  <meta name="description" content="{{$description}}" />
  <title>{{$title}}</title>
  @if(!empty($logo))
  <link rel="icon" href="{{ $logo }}" />
  <link rel="apple-touch-icon" href="{{ $logo }}" />
  @else
  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%230071e3'/%3E%3Ctext x='32' y='44' font-size='34' font-family='-apple-system,Helvetica,Arial,sans-serif' font-weight='700' fill='white' text-anchor='middle'%3EA%3C/text%3E%3C/svg%3E" />
  @endif
  <link rel="stylesheet" href="{{ $assetPath }}/app.css" />
</head>
<body>
<script>
  window.routerBase = "/";
  window.settings = {
    title: @json($title ?? ''),
    description: @json($description ?? ''),
    assets_path: @json($assetPath),
    theme: { color: @json($theme_config['theme_color'] ?? 'default') },
    version: @json($version ?? ''),
    background_url: @json($theme_config['background_url'] ?? ''),
    logo: @json($logo ?? ''),
    downloads: {
      android: @json($theme_config["android_url"] ?? ""),
      windows: @json($theme_config["windows_url"] ?? ""),
      macos: @json($theme_config["macos_url"] ?? ""),
      ios: @json($theme_config["ios_url"] ?? "")
    },
    i18n: ['zh-CN', 'en-US']
  };
</script>
<div id="app"></div>
<script type="module" src="{{ $assetPath }}/app.js"></script>
{!! $theme_config['custom_html'] ?? '' !!}
</body>
</html>
