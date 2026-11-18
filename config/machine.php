<?php

return [
    'ssh_gateway_url' => env('XBOARD_SSH_GATEWAY_URL', ''),
    'ssh_connections' => env('XBOARD_SSH_CONNECTIONS', ''),
    'installer_url' => env('XBOARD_NODE_INSTALLER_URL', 'https://raw.githubusercontent.com/Furina-Lee/Xboard-Node/v1.13-furina.1/install.sh'),
    'installer_version' => env('XBOARD_NODE_INSTALLER_VERSION', 'v1.13-furina.1'),
];
