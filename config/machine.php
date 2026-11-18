<?php

return [
    'ssh_gateway_url' => env('XBOARD_SSH_GATEWAY_URL', ''),
    'ssh_connections' => env('XBOARD_SSH_CONNECTIONS', ''),
    'installer_url' => env('XBOARD_NODE_INSTALLER_URL', 'https://raw.githubusercontent.com/cedar2025/xboard-node/v1.13/install.sh'),
    'installer_version' => env('XBOARD_NODE_INSTALLER_VERSION', 'v1.13'),
];
