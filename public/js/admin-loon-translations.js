(() => {
  const translations = {
    "zh-CN": {
      title: "Loon 通用订阅下发完整配置",
      description: "开启后，Loon 可使用通用订阅链接导入远程配置。继续订阅节点时，请在链接中加上 format=loon-nodes。",
    },
    "en-US": {
      title: "Full Loon configuration from the standard subscription",
      description: "When enabled, Loon can import the standard subscription URL as a remote configuration. Add format=loon-nodes to keep using a node subscription.",
    },
    "ru-RU": {
      title: "Полная конфигурация Loon по общей ссылке подписки",
      description: "После включения Loon сможет импортировать общую ссылку подписки как удалённую конфигурацию. Для подписки на узлы добавьте format=loon-nodes.",
    },
  };

  const resources = (window.XBOARD_TRANSLATIONS ??= {});
  for (const [language, fallback] of Object.entries(translations)) {
    const settings = ((resources[language] ??= {}).settings ??= {});
    const subscribe = (settings.subscribe ??= {});
    subscribe.loon_full_config = { ...fallback, ...subscribe.loon_full_config };
  }
})();

