<?php

namespace App\WebSocket;

use App\Models\Server;
use App\Services\DeviceStateService;
use App\Services\NodeRegistry;
use App\Services\ServerService;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Workerman\Connection\TcpConnection;

class NodeEventHandlers
{
    /**
     * Handle pong heartbeat
     */
    public static function handlePong(TcpConnection $conn, int $nodeId, array $data = []): void
    {
        Cache::put("node_ws_alive:{$nodeId}", true, 86400);
    }

    public static function handleTrafficReport(TcpConnection $conn, int $nodeId, array $data): void
    {
        $reportId = $data['report_id'] ?? null;
        $traffic = $data['traffic'] ?? null;
        if (!is_string($reportId) || !preg_match('/\A[a-f0-9]{32}\z/', $reportId)
            || !is_array($traffic) || !$traffic || count($traffic) > 50000) {
            return;
        }

        $node = Server::find($nodeId);
        if (!$node) {
            $conn->send(json_encode([
                'event' => 'report.traffic.ack',
                'data' => ['node_id' => $nodeId, 'report_id' => $reportId, 'accepted' => false],
            ]));
            return;
        }

        try {
            ServerService::touchNode($node);
            ServerService::processTraffic($node, $traffic, $reportId);
        } catch (\Throwable $error) {
            report($error);
            return;
        }

        $conn->send(json_encode([
            'event' => 'report.traffic.ack',
            'data' => ['node_id' => $nodeId, 'report_id' => $reportId, 'accepted' => true],
        ]));
    }

    /**
     * Handle node status update
     */
    public static function handleNodeStatus(TcpConnection $conn, int $nodeId, array $data): void
    {
        $node = Server::find($nodeId);
        if (!$node) return;

        $nodeType = strtoupper($node->type);
        Cache::put(\App\Utils\CacheKey::get('SERVER_' . $nodeType . '_LAST_CHECK_AT', $nodeId), time(), 3600);
        ServerService::updateMetrics($node, $data);

        Log::debug("[WS] Node#{$nodeId} status updated");
    }

    /**
     * Handle device report from node
     * 
     * 数据格式: {"event": "report.devices", "data": {userId: [ip1, ip2, ...], ...}}
     */
    public static function handleDeviceReport(TcpConnection $conn, int $nodeId, array $data): void
    {
        $service = app(DeviceStateService::class);

        if (isset($data['devices']) && is_array($data['devices'])) {
            $data = $data['devices'];
        }

        // Get old data
        $oldDevices = $service->getNodeDevices($nodeId);

        // Calculate diff
        $removedUsers = array_diff_key($oldDevices, $data);
        $newDevices = [];

        foreach ($data as $userId => $ips) {
            if (is_numeric($userId) && is_array($ips)) {
                $newDevices[(int) $userId] = $ips;
            }
        }

        // Handle removed users
        foreach ($removedUsers as $userId => $ips) {
            $service->removeNodeDevices($nodeId, $userId);
            $service->notifyUpdate($userId);
        }

        // Handle new/updated users
        foreach ($newDevices as $userId => $ips) {
            $service->setDevices($userId, $nodeId, $ips);
        }

        // Mark for push
        Redis::sadd('device:push_pending_nodes', $nodeId);

        Log::debug("[WS] Node#{$nodeId} synced " . count($newDevices) . " users, removed " . count($removedUsers));
    }

    /**
     * Handle device state request from node
     */
    public static function handleDeviceRequest(TcpConnection $conn, int $nodeId, array $data = []): void
    {
        $node = Server::find($nodeId);
        if (!$node) return;

        $users = ServerService::getAvailableUsers($node);
        $userIds = $users->pluck('id')->toArray();

        $service = app(DeviceStateService::class);
        $devices = $service->getUsersDevices($userIds);

        NodeRegistry::send($nodeId, 'sync.devices', [
            'users' => $devices,
        ]);

        Log::debug("[WS] Node#{$nodeId} requested devices, sent " . count($devices) . " users");
    }

    /**
     * Push device state to node
     */
    public static function pushDeviceStateToNode(int $nodeId, DeviceStateService $service): void
    {
        $node = Server::find($nodeId);
        if (!$node) return;

        $users = ServerService::getAvailableUsers($node);
        $userIds = $users->pluck('id')->toArray();
        $devices = $service->getUsersDevices($userIds);

        NodeRegistry::send($nodeId, 'sync.devices', [
            'users' => $devices
        ]);

        Log::debug("[WS] Pushed device state to node#{$nodeId}: " . count($devices) . " users");
    }

    /**
     * Push full config + users to newly connected node
     */
    public static function pushFullSync(TcpConnection $conn, Server $node): void
    {
        $nodeId = (int) $node->id;

        // Push config
        $config = ServerService::buildNodeConfig($node);
        NodeRegistry::send($nodeId, 'sync.config', [
            'config' => $config,
        ]);

        // Push users
        $users = ServerService::getAvailableUsers($node)->toArray();
        NodeRegistry::send($nodeId, 'sync.users', [
            'users' => $users,
        ]);

        Log::info("[WS] Full sync pushed to node#{$nodeId}", [
            'users' => count($users),
        ]);
    }
}
