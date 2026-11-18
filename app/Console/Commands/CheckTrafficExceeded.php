<?php

namespace App\Console\Commands;

use App\Services\NodeSyncService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Redis;

class CheckTrafficExceeded extends Command
{
    protected $signature = 'check:traffic-exceeded';
    protected $description = '检查流量超标用户并通知节点';

    public function handle()
    {
        $count = Redis::scard('traffic:pending_check');
        if ($count <= 0) {
            return;
        }

        $pendingUserIds = array_map('intval', Redis::spop('traffic:pending_check', $count));

        $notifiedCount = NodeSyncService::notifyQuotaExceeded($pendingUserIds);
        $this->info("Checked " . count($pendingUserIds) . " users and notified {$notifiedCount} nodes.");
    }
}
