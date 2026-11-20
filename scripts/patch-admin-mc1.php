<?php

// Xboard ships its admin frontend as a pinned, prebuilt submodule.
$root = $argv[1] ?? dirname(__DIR__) . '/public/assets/admin';
$manifestFile = $root . '/manifest.json';
$manifest = json_decode(file_get_contents($manifestFile), true, 512, JSON_THROW_ON_ERROR);
$entry = $manifest['index.html']['file'];
$source = file_get_contents($root . '/' . $entry);
if (str_contains($source, 'function xboardGenerateMc1Template(')) {
    exit(0);
}

function replaceOnce(string $source, string $before, string $after): string
{
    if (substr_count($source, $before) !== 1) {
        throw new RuntimeException('Unsupported admin bundle: ' . substr($before, 0, 120));
    }

    return str_replace($before, $after, $source);
}

$helpers = <<<'JS'
function xboardMc1Random(size) {
  return Array.from(crypto.getRandomValues(new Uint8Array(size)),
    byte => byte.toString(16).padStart(2, "0")).join("");
}
function xboardGenerateMc1Sni() {
  return "mx-" + xboardMc1Random(6) + ".example";
}
function xboardSetMc1Sni(form, previous, next) {
  const settings = form.getValues("network_settings") || {};
  if (!settings.host || settings.host === previous) {
    form.setValue("network_settings", {...settings, host: next}, {shouldDirty: true});
  }
}
function xboardGenerateMc1Template(form) {
  let sni = (form.getValues("tls_settings.server_name") || "").trim();
  if (!sni) {
    sni = xboardGenerateMc1Sni();
    form.setValue("tls_settings.server_name", sni, {shouldDirty: true});
  }
  return {host: sni, mode: "auto", path: "/" + xboardMc1Random(8)};
}
function xboardMxForm(props) {
  return Q.jsx(k4t, {...props, mxMode: true});
}
function xboardMc1SniControl(form, field, t) {
  const label = {"zh-CN": "随机生成 SNI", "ru-RU": "Сгенерировать SNI"}[lL.language] || "Generate random SNI";
  const input = Q.jsx(u8e, {
    className: "font-mono text-xs min-w-0",
    placeholder: t("dynamic_form.vmess.tls_settings.server_name.placeholder"),
    ...field,
    onChange(event) {
      const next = event.target.value;
      xboardSetMc1Sni(form, field.value, next);
      field.onChange(event);
    },
  });
  return Q.jsxs("div", {className: "flex items-center gap-2", children: [
    Q.jsx(Yy, {children: input}),
    Q.jsx(Lf, {type: "button", variant: "outline", size: "icon", className: "shrink-0",
      title: label, "aria-label": label, onClick() {
        const next = xboardGenerateMc1Sni();
        xboardSetMc1Sni(form, field.value, next);
        field.onChange(next);
      }, children: Q.jsx("span", {"aria-hidden": true, children: "⟳"})}),
  ]});
}
JS;

$source = replaceOnce($source, 'function m4t({dialogTrigger:e,value:t,setValue:n,templateType:i})',
    "\n" . $helpers . "\n" . 'function m4t({dialogTrigger:e,value:t,setValue:n,templateType:i,mc1Template:mxTemplate})');
$source = replaceOnce($source, 'case"xhttp":return["xhttp"];default:return[]',
    'case"xhttp":return["xhttp"];case"mc1":return mxTemplate?["mc1"]:[];default:return[]');
$source = replaceOnce($source, 'const e=JSON.stringify(t.content,null,2);l(e),d(null)',
    'const a=JSON.stringify(e==="mc1"&&mxTemplate?mxTemplate():t.content,null,2);l(a),d(null)');
$source = replaceOnce($source, 'mx:{schema:C4t(e,t),component:k4t}',
    'mx:{schema:C4t(e,t),component:xboardMxForm}');
$source = replaceOnce($source, 'k4t=({form:e,t:t})=>',
    'k4t=({form:e,t:t,mxMode:mxMode})=>');
$source = replaceOnce($source,
    'name:"tls_settings.server_name",render:({field:e})=>Q.jsxs(Gy,{className:"flex-[2]",children:[Q.jsx(Zy,{className:"text-[12px] font-mono text-foreground/80",children:t("dynamic_form.vmess.tls_settings.server_name.label")}),Q.jsx(Yy,{children:Q.jsx(u8e,{className:"font-mono text-xs",placeholder:t("dynamic_form.vmess.tls_settings.server_name.placeholder"),...e})})]',
    'name:"tls_settings.server_name",render:({field:n})=>Q.jsxs(Gy,{className:"flex-[2]",children:[Q.jsx(Zy,{className:"text-[12px] font-mono text-foreground/80",children:t("dynamic_form.vmess.tls_settings.server_name.label")}),mxMode&&e.watch("network")==="mc1"?xboardMc1SniControl(e,n,t):Q.jsx(Yy,{children:Q.jsx(u8e,{className:"font-mono text-xs",placeholder:t("dynamic_form.vmess.tls_settings.server_name.placeholder"),...n})})]');
if (substr_count($source, 'templateType:e.watch("network")})]') < 1) {
    throw new RuntimeException('Unsupported admin bundle: network settings editor');
}
$position = strpos($source, 'templateType:e.watch("network")})]', strpos($source, 'k4t=({form:e,t:t,mxMode:mxMode})'));
$source = substr_replace($source,
    'templateType:e.watch("network"),mc1Template:mxMode?()=>xboardGenerateMc1Template(e):undefined})]',
    $position, strlen('templateType:e.watch("network")})]'));

$name = 'assets/index-mc1-' . substr(hash('sha256', $source), 0, 12) . '.js';
file_put_contents($root . '/' . $name, $source);
$manifest['index.html']['file'] = $name;
file_put_contents($manifestFile, json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n");

