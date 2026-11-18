<?php

namespace App\Jobs;

use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Redis;

class TrafficFetchJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;
    protected $data;
    protected $server;
    protected $protocol;
    protected $timestamp;
    public $tries = 1;
    public $timeout = 20;

    public function __construct(array $server, array $data, $protocol, int $timestamp)
    {
        $this->onQueue('traffic_fetch');
        $this->server = $server;
        $this->data = $data;
        $this->protocol = $protocol;
        $this->timestamp = $timestamp;
    }

    public function handle(): void
    {
        self::record($this->data, $this->server['rate']);

        if ($this->data !== []) {
            Redis::sadd('traffic:pending_check', ...array_keys($this->data));
        }
    }

    public static function record(array $data, float $rate): void
    {
        ksort($data, SORT_NUMERIC);

        foreach ($data as $uid => $v) {
            User::where('id', $uid)
                ->incrementEach(
                    [
                        'u' => $v[0] * $rate,
                        'd' => $v[1] * $rate,
                    ],
                    ['t' => time()]
                );
        }
    }
}
